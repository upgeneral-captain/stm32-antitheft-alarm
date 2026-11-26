/**
  ******************************************************************************
  * @file    key.h
  * @brief   按键扫描（PB8 设防 / PB9 撤防）：10ms 消抖 + 事件队列 + 撤防密码
  ******************************************************************************
  */

#ifndef __KEY_H
#define __KEY_H

#include "stm32f1xx_hal.h"

typedef enum {
    KEY_NONE   = 0,
    KEY_ARM    = 1,     /* PB8 */
    KEY_DISARM = 2      /* PB9 */
} KeyId;

/* 一次有效按键事件（按下瞬间产生一次） */
typedef struct {
    KeyId   id;
    uint8_t longPress;  /* 1 = 长按释放后补发的（本工程只用于撤防强制退出） */
} KeyEvent;

/* 密码进度 */
typedef enum {
    PWD_STEP_IDLE   = 0,    /* 还没开始 */
    PWD_STEP_GOT_9  = 1,    /* 已按第 1 步 PB9 */
    PWD_STEP_GOT_98 = 2     /* 已按 PB9 -> PB8，等待最后一个 PB9 */
} KeyPwdState;

void Key_Init(void);

/* 每 10ms 调一次：采样 + 消抖 + 入队 */
void Key_Scan10ms(void);

/* 取一个事件（非阻塞），1 = 取到 */
uint8_t Key_GetEvent(KeyEvent *evt);

/* 清空事件队列 */
void Key_FlushEvents(void);
void Key_ResetPassword(void);

/**
 * @brief 把一次按键事件喂给密码检测器
 * @retval 1 = 密码正确（PB9 -> PB8 -> PB9，每步 3 秒内）
 */
uint8_t Key_FeedPassword(KeyId key);

/* 当前密码进度（OLED 显示用，内部会顺手做超时清理） */
KeyPwdState Key_GetPwdState(void);

/* 撤防键是否已被长按超过 KEY_LONG_PRESS_MS（应急强制撤防） */
uint8_t Key_IsDisarmLongPressed(void);

#endif /* __KEY_H */
