/**
  ******************************************************************************
  * @file    key.c
  * @brief   按键扫描：10ms 消抖 + 事件队列 + 撤防密码序列检测
  *
  * 消抖原理：
  *   按键由主循环每 10ms 采样一次；连续 2 次采样电平相同才认为“稳定”，
  *   等价于 10~20ms 的硬件消抖时间，满足需求书“10ms 软件消抖”。
  *   只在“稳定电平发生翻转”的时刻生产事件：
  *       1 -> 0  下降沿 = 按下（推一条事件）
  *       0 -> 1  上升沿 = 松开（若按住超过 KEY_LONG_PRESS_MS 再补一条 longPress 事件）
  ******************************************************************************
  */

#include "key.h"
#include "config.h"
#include "main.h"

/* ====================== 事件队列（环形，8 条） ====================== */
#define KEY_QUEUE_SIZE   8

static KeyEvent key_queue[KEY_QUEUE_SIZE];
static uint8_t  q_head = 0;
static uint8_t  q_tail = 0;

/* ====================== 每个按键的消抖状态 ====================== */
typedef struct {
    uint8_t  last_raw;      /* 上次采样电平（1=松开，0=按下） */
    uint8_t  stable;        /* 已确认的稳定电平 */
    uint8_t  same_cnt;      /* 连续相同采样次数 */
    uint32_t press_tick;    /* 按下时刻 */
} KeyState;

static KeyState key_arm;
static KeyState key_disarm;

/* ====================== 密码检测 ====================== */
static KeyPwdState pwd_state     = PWD_STEP_IDLE;
static uint32_t    pwd_last_tick = 0;

/* 上电稳定标志：前 300ms 不产生事件，避开电源抖动的假按键 */
static uint8_t  key_ready   = 0;
static uint32_t boot_tick   = 0;
static uint8_t  boot_inited = 0;

static uint8_t ReadArmPin(void)
{
    return (HAL_GPIO_ReadPin(KEY_ARM_GPIO_Port, KEY_ARM_Pin) == GPIO_PIN_SET) ? 1 : 0;
}

static uint8_t ReadDisarmPin(void)
{
    return (HAL_GPIO_ReadPin(KEY_DISARM_GPIO_Port, KEY_DISARM_Pin) == GPIO_PIN_SET) ? 1 : 0;
}

static void PushEvent(KeyId id, uint8_t longPress)
{
    uint8_t next = (uint8_t)((q_head + 1) % KEY_QUEUE_SIZE);

    if (next == q_tail) {
        /* 队列满：丢掉最旧的一条，保证最新的按键（密码最后一步）不丢 */
        q_tail = (uint8_t)((q_tail + 1) % KEY_QUEUE_SIZE);
    }
    key_queue[q_head].id        = id;
    key_queue[q_head].longPress = longPress;
    q_head = next;
}

void Key_Init(void)
{
    q_head = 0;
    q_tail = 0;

    pwd_state     = PWD_STEP_IDLE;
    pwd_last_tick = 0;

    key_ready   = 0;
    boot_tick   = HAL_GetTick();
    boot_inited = 1;

    key_arm.last_raw     = ReadArmPin();
    key_arm.stable       = key_arm.last_raw;
    key_arm.same_cnt     = 0;
    key_arm.press_tick   = 0;

    key_disarm.last_raw  = ReadDisarmPin();
    key_disarm.stable    = key_disarm.last_raw;
    key_disarm.same_cnt  = 0;
    key_disarm.press_tick = boot_tick;
}

/**
 * @brief 单个按键的消抖 + 边沿检测
 * @param st  按键状态
 * @param raw 本次采样电平（1=松开，0=按下）
 * @param id  按键编号
 */
static void ScanOneKey(KeyState *st, uint8_t raw, KeyId id)
{
    if (raw != st->last_raw) {
        /* 电平变了：重新计数，先不判定（可能只是抖动） */
        st->last_raw = raw;
        st->same_cnt = 0;
        return;
    }

    /* 电平与上次相同：累计稳定次数 */
    if (st->same_cnt < 2) st->same_cnt++;

    /* 连续 2 次采样（=10~20ms）一致 -> 确认新电平 */
    if (st->same_cnt >= 2 && raw != st->stable) {
        st->stable = raw;

        if (st->stable == 0) {
            /* 下降沿：按下 */
            st->press_tick = HAL_GetTick();
            if (key_ready) PushEvent(id, 0);
        } else {
            /* 上升沿：松开；按住超过长按时间就补一条 longPress 事件 */
            if (key_ready && (HAL_GetTick() - st->press_tick) >= KEY_LONG_PRESS_MS) {
                PushEvent(id, 1);
            }
        }
    }
}

void Key_Scan10ms(void)
{
    if (!boot_inited) return;

    if (!key_ready) {
        if ((HAL_GetTick() - boot_tick) > 300U) key_ready = 1;
        return;                        /* 上电 300ms 内不产生按键事件 */
    }

    ScanOneKey(&key_arm,    ReadArmPin(),    KEY_ARM);
    ScanOneKey(&key_disarm, ReadDisarmPin(), KEY_DISARM);
}

uint8_t Key_GetEvent(KeyEvent *evt)
{
    if (q_tail == q_head) return 0;
    *evt = key_queue[q_tail];
    q_tail = (uint8_t)((q_tail + 1) % KEY_QUEUE_SIZE);
    return 1;
}

void Key_ResetPassword(void) { pwd_state=PWD_STEP_IDLE; pwd_last_tick=0; }

void Key_FlushEvents(void)
{
    q_tail = q_head;
}

/* ====================== 撤防密码：PB9 -> PB8 -> PB9 ====================== */

/**
 * @brief 密码序列检测
 * @note  规则（对应需求 5）：
 *          第 1 步：按撤防键 PB9  -> GOT_9
 *          第 2 步：按设防键 PB8  -> GOT_98
 *          第 3 步：按撤防键 PB9  -> 正确
 *        任意一步距上一步超过 3 秒 -> 进度清零，必须从第 1 步重来；
 *        在错误步骤按错键 -> 立即作废。
 */
uint8_t Key_FeedPassword(KeyId key)
{
    uint32_t now = HAL_GetTick();

    /* 步骤超时检查：超过 3 秒就作废 */
    if (pwd_state != PWD_STEP_IDLE &&
        (now - pwd_last_tick) > PASSWORD_STEP_TIMEOUT_MS) {
        pwd_state = PWD_STEP_IDLE;
    }

    switch (pwd_state)
    {
    case PWD_STEP_IDLE:
        if (key == KEY_DISARM) {
            pwd_state     = PWD_STEP_GOT_9;      /* 第 1 步正确 */
            pwd_last_tick = now;
        } else if (key == KEY_ARM) {
            /* 第 1 步按错：ALARM 下 PB8 没别的用途，宽容处理，只刷新计时 */
            pwd_last_tick = now;
        }
        break;

    case PWD_STEP_GOT_9:
        if (key == KEY_ARM) {
            pwd_state     = PWD_STEP_GOT_98;     /* 第 2 步正确 */
            pwd_last_tick = now;
        } else if (key == KEY_DISARM) {
            /* 连按两次撤防键：当作重新开始第 1 步 */
            pwd_last_tick = now;
        }
        break;

    case PWD_STEP_GOT_98:
        if (key == KEY_DISARM) {
            pwd_state = PWD_STEP_IDLE;           /* 第 3 步正确 */
            return 1;
        } else if (key == KEY_ARM) {
            pwd_state = PWD_STEP_IDLE;           /* 按错 -> 作废重来 */
        }
        break;

    default:
        pwd_state = PWD_STEP_IDLE;
        break;
    }
    return 0;
}

KeyPwdState Key_GetPwdState(void)
{
    /* 顺手清理超时，保证 OLED 显示的是真实进度 */
    if (pwd_state != PWD_STEP_IDLE &&
        (HAL_GetTick() - pwd_last_tick) > PASSWORD_STEP_TIMEOUT_MS) {
        pwd_state = PWD_STEP_IDLE;
    }
    return pwd_state;
}

uint8_t Key_IsDisarmLongPressed(void)
{
    return (uint8_t)(key_ready && (key_disarm.stable == 0) &&
                     ((HAL_GetTick() - key_disarm.press_tick) >= KEY_LONG_PRESS_MS));
}
