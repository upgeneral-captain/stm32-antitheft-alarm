/**
  ******************************************************************************
  * @file    main.c
  * @brief   智能防丢防盗震动报警器 —— 主循环 + 4 状态状态机
  *
  * ┌──────────────────────────────────────────────────────────────────────┐
  * │                           状态转换图                                  │
  * │                                                                      │
  * │      [上电]                                                           │
  * │         │                                                            │
  * │         ▼                                                            │
  * │   ┌───────────┐   按 PB8(设防键)      ┌───────────┐                   │
  * │   │ DISARMED  │ ───────────────────► │  ARMING   │                  │
  * │   │  撤防      │                      │ 设防延时10s│                  │
  * │   │ 绿灯亮     │ ◄───────────┐        └─────┬─────┘                  │
  * │   └───────────┘             │              │ 倒计时到 0              │
  * │         ▲                   │              ▼                        │
  * │         │                   │        ┌───────────┐                   │
  * │         │ 密码 PB9→PB8→PB9   │        │  ARMED    │                  │
  * │         │ (每步 3s 内)        │        │ 设防检测   │                  │
  * │         │                   │        └─────┬─────┘                  │
  * │         │                   │  偏差>HIGH 连续 10 次 │                 │
  * │         │                   │              ▼                        │
  * │         │                   └──────── ┌───────────┐                  │
  * │         └───────────────────────────── │   ALARM   │                 │
  * │                    密码正确             │ 报警+推送  │                 │
  * │                                       └───────────┘                  │
  * │   （ARMING 状态下按 PB9 可取消，直接回 DISARMED）                       │
  * │   （ALARM 状态下长按 PB9 两秒可强制撤防）                               │
  * └──────────────────────────────────────────────────────────────────────┘
  *
  * 主循环节拍：10ms 一次（用 HAL_GetTick 判断，不额外占用定时器中断）
  ******************************************************************************
  */

/* Includes ------------------------------------------------------------------*/
#include "main.h"
#include "config.h"
#include "oled.h"
#include "mpu6050.h"
#include "key.h"
#include "alarm.h"
#include "esp8266.h"
#include "gps.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include "settings.h"

/* Private variables ---------------------------------------------------------*/
I2C_HandleTypeDef hi2c1;
UART_HandleTypeDef huart1;
UART_HandleTypeDef huart2;

/* ====================== 状态机定义 ====================== */
typedef enum {
    STATE_DISARMED = 0,   /* 撤防：绿灯亮，不检测 */
    STATE_ARMING,         /* 设防延时倒计时（10s） */
    STATE_ARMED,          /* 已设防，检测震动 */
    STATE_FAULT,
    STATE_ALARM           /* 报警中 */
} SysState;

static SysState  g_state       = STATE_DISARMED;
static uint32_t  g_state_tick  = 0;      /* 进入当前状态的时刻 */
static uint8_t g_status_dirty=1, g_was_connected=0;
static char g_ack[33], g_ack_result[12];
static uint32_t g_boot_id;
static uint8_t g_sensor_ok;
static uint8_t g_sensor_errors;
#define SENSOR_ERROR_LIMIT 3U
static uint32_t g_last_sample = 0;      /* 上次 10ms 节拍时刻 */
static uint32_t  g_last_report = 0;      /* 上次网络推送时刻 */
static uint32_t  g_last_beep   = 0;      /* 上次倒计时提示音时刻 */
static uint32_t  g_last_ui     = 0;      /* 上次刷屏时刻 */

static uint8_t   g_over_count  = 0;      /* 连续超阈值次数（防误报计数） */
static uint32_t  g_alarm_count = 0;      /* 本次运行累计报警次数（调试用） */
static uint8_t   g_gps_ready   = 0;      /* 本次报警是否已带 GPS 坐标推送过 */
static uint32_t  g_last_state_report = 0; /* 上次状态心跳上报时刻 */
static uint32_t  g_last_gps_report   = 0; /* 上次 GPS 上报时刻 */

/* 调试信息（OLED 显示用） */
static float     g_dbg_dev     = 0.0f;   /* 最近一次震动偏差 */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
static void MX_GPIO_Init(void);
static void MX_I2C1_Init(void);
static void MX_USART1_UART_Init(void);
static void MX_USART2_UART_Init(void);

static void App_Init(void);
static void App_Loop10ms(void);
static void App_StateMachine(KeyEvent *evt, uint8_t hasEvent);
static void App_EnterState(SysState s);
static void App_UpdateOLED(void);
static void App_ReportAlarm(void);
static void App_MqttPoll(void);
static void App_OnMqttCmd(const char *cmd);

/* ============================================================================
 *  main
 * ==========================================================================*/
int main(void)
{
  HAL_Init();
  SystemClock_Config();          /* 72MHz：HSE 8M × PLL9 */

  /* 外设初始化 */
  MX_GPIO_Init();
  MX_I2C1_Init();
  MX_USART1_UART_Init();
  MX_USART2_UART_Init();

  /* 应用层初始化 */
  App_Init();

  /* 主循环 */
  while (1)
  {
      /* GPS：持续把串口数据解析成经纬度（与状态无关，一直跑） */
      GPS_Task();

      /* MQTT：处理收到的命令 + 保活 + 周期上报 */
      App_MqttPoll();

      /* 10ms 节拍：按键扫描 + 状态机 + 报警节奏 */
      if ((HAL_GetTick() - g_last_sample) >= MPU_SAMPLE_PERIOD_MS) {
          g_last_sample = HAL_GetTick();
          App_Loop10ms();
      }

      Alarm_Tick();
      if(HAL_GetTick()-g_last_sample < 6U) OLED_Task();

      /* OLED 200ms 刷新一次（刷太快没意义，还拖慢 I2C 总线） */
      if ((HAL_GetTick() - g_last_ui) >= 200U) {
          g_last_ui = HAL_GetTick();
          App_UpdateOLED();
      }
  }
}

/* ============================================================================
 *  初始化
 * ==========================================================================*/
static void App_Init(void)
{
    /* --- 输出先全部复位到安全电平（蜂鸣器不响、灯灭） --- */
    BUZZER_OFF();
    LED_R_OFF();
    LED_G_OFF();

    /* --- 屏幕 --- */
    OLED_Init(&hi2c1);
    OLED_PrintLine(0, 0, "SMART ALARM V1.0.2");
    OLED_PrintLine(0, 2, "MPU6050 INIT...");

    /* --- IMU（此时设备必须静止，基准才准） --- */
    g_sensor_ok = (MPU6050_Init(&hi2c1) == 0);
    if (!g_sensor_ok) {
        OLED_PrintLine(0, 3, "MPU6050: NOT FOUND");
    } else {
        OLED_PrintLineFloat(0, 3, "MPU6050 OK REF=", MPU6050_GetRefMag(), 1, 3, "g");
    }

    /* --- 按键 --- */
    Key_Init();

    /* --- 报警输出 --- */
    Alarm_Init();

    /* --- GPS（同时启动 USART2 中断接收） --- */
    GPS_Init();

    /* Start networking asynchronously; local protection does not wait for Wi-Fi. */
    ESP8266_SetCmdCallback(App_OnMqttCmd);
    ESP8266_Init();
    uint8_t restored=Settings_Load();
    g_boot_id=Settings_BootId();
    if(!g_sensor_ok) App_EnterState(STATE_FAULT);
    else App_EnterState(restored ? STATE_ARMING : STATE_DISARMED);
    g_last_sample = HAL_GetTick();
    g_last_ui     = HAL_GetTick();
}

/* ============================================================================
 *  10ms 节拍
 * ==========================================================================*/
static void App_Loop10ms(void)
{
    KeyEvent evt;
    uint8_t  hasEvent;

    /* 1) 按键扫描（内部 10ms 消抖） */
    Key_Scan10ms();

    /* 2) 一次只处理一个事件，保证密码顺序不乱 */
    hasEvent = Key_GetEvent(&evt);

    /* 3) 状态机 */
    App_StateMachine(hasEvent ? &evt : NULL, hasEvent);

    /* 4) 报警节奏推进（非阻塞） */
    Alarm_Tick();
}

/* ============================================================================
 *  状态机：4 个状态 + 转换条件
 * ==========================================================================*/
/* Invalid samples cannot extend the vibration counter or finish arming. */
static uint8_t App_CheckSensor(void)
{
    if (!MPU6050_IsOnline()) {
        g_over_count=0;
        if (++g_sensor_errors >= SENSOR_ERROR_LIMIT) {
            g_sensor_ok=0;
            App_EnterState(STATE_FAULT);
        }
        return 0;
    }
    g_sensor_errors=0;
    return 1;
}

static void App_StateMachine(KeyEvent *evt, uint8_t hasEvent)
{
    uint32_t now = HAL_GetTick();
    KeyId key = (hasEvent && !evt->longPress) ? evt->id : KEY_NONE;

    switch (g_state)
    {
    /* ---------------- 1. DISARMED 撤防 ---------------- */
    case STATE_FAULT:
        LED_R_ON(); LED_G_OFF();
        if (key == KEY_ARM) {
            g_sensor_ok=(MPU6050_Init(&hi2c1)==0);
            if(g_sensor_ok) App_EnterState(STATE_ARMING);
        }
        if (key == KEY_DISARM && g_sensor_ok) App_EnterState(STATE_DISARMED);
        else if (key == KEY_DISARM) (void)Settings_Save(0);
        break;
    case STATE_DISARMED:
        Alarm_SetLevel(ALARM_LEVEL_NONE);   /* 静音 */
        LED_G_ON();                         /* 绿灯亮 */
        LED_R_OFF();
        g_over_count = 0;
        g_gps_ready  = 0;

        /* 转换：按设防键 -> ARMING */
        if (key == KEY_ARM) {
            App_EnterState(STATE_ARMING);
        }
        break;

    /* ---------------- 2. ARMING 设防延时 ---------------- */
    case STATE_ARMING:
    {
        uint32_t elapsed = now - g_state_tick;

        LED_R_ON();                         /* 延时期间红灯常亮 */
        LED_G_OFF();
        g_over_count = 0;

        if (key == KEY_DISARM) {
            App_EnterState(STATE_DISARMED);
            break;
        }

        g_dbg_dev=MPU6050_GetDeviation();
        if (!App_CheckSensor()) break;

        /* 每满 1 秒“嘀”一声，提示正在倒计时 */
        if ((elapsed / 1000U) > (g_last_beep / 1000U)) {
            g_last_beep = elapsed;
            Alarm_BeepOnce();
        }

        /* 转换：倒计时结束 -> ARMED */
        if (elapsed >= ARM_DELAY_MS) {
            App_EnterState(STATE_ARMED);
            break;
        }

        break;
    }

    /* ---------------- 3. ARMED 已设防（核心检测） ---------------- */
    case STATE_ARMED:
    {
        float dev;

        LED_G_OFF();                        /* 设防后两灯都灭（省电、不引人注意） */
        LED_R_OFF();

        if (key == KEY_DISARM) {
            App_EnterState(STATE_DISARMED);
            break;
        }

        /* 采样 + 计算偏差：每 10ms 一次 */
        dev = MPU6050_GetDeviation();
        g_dbg_dev = dev;
        if (!App_CheckSensor()) break;

        if (dev >= THRESH_HIGH) {
            /* ---- 超高阈值：计数 +1，必须连续 N 次才真正报警 ---- */
            if (g_over_count < 255) g_over_count++;

            if (g_over_count >= ALARM_CONFIRM_COUNT) {
                /* 连续 10 次（≈100ms）都超阈值 -> 确认真实震动，进入 ALARM */
                g_alarm_count++;
                App_EnterState(STATE_ALARM);
                break;
            }
            /* 还没到确认次数：先“嘀”一下作为即时反馈，但不进入 ALARM，
             * 这样偶尔碰一下只响一声，不会惊动邻居 */
            Alarm_SetLevel(ALARM_LEVEL_NOTIFY);
        }
        else if (dev >= THRESH_LOW) {
            /* ---- 低阈值区：轻碰/微晃 ----
             * 计数器清零：高阈值要求“连续”，中途掉回低区就重新计数 */
            g_over_count = 0;
            Alarm_SetLevel(ALARM_LEVEL_NOTIFY);
        }
        else {
            /* ---- 平静：合加速度接近基准 ---- */
            g_over_count = 0;
            Alarm_SetLevel(ALARM_LEVEL_NONE);
        }

        break;
    }

    /* ---------------- 4. ALARM 报警 ---------------- */
    case STATE_ALARM:
    {
        LED_G_OFF();
        Alarm_SetLevel(ALARM_LEVEL_FULL);   /* 连续高分贝 + 红灯闪烁 */

        /* 4.1 撤防密码：PB9 -> PB8 -> PB9，每步 3 秒内完成 */
        if (key != KEY_NONE) {
            if (Key_FeedPassword(key)) {
                App_EnterState(STATE_DISARMED);   /* 密码正确 -> 撤防 */
                break;
            }
        }

        /* 4.2 长按撤防键 2 秒 -> 强制撤防（应急：密码忘了 / 按键坏了） */
        if (Key_IsDisarmLongPressed()) {
            App_EnterState(STATE_DISARMED);
            break;
        }

        /* 4.3 网络推送：进入报警先推一次，之后每 60 秒重复一次 */
        if ((now - g_last_report) >= REPORT_INTERVAL_MS && !ESP8266_IsBusy()) {
            g_last_report = now;
            App_ReportAlarm();
        }
        break;
    }

    default:
        App_EnterState(STATE_DISARMED);
        break;
    }
}

/* ============================================================================
 *  状态切换：所有“进入某状态时要执行的动作”集中在这里
 * ==========================================================================*/
static void App_EnterState(SysState s)
{
    if (s==STATE_ARMING && !g_sensor_ok) s=STATE_FAULT;
    if (s==STATE_ARMING || s==STATE_DISARMED) {
        if (!Settings_Save(s==STATE_ARMING) || !g_sensor_ok) s=STATE_FAULT;
    }
    g_sensor_errors=0;
    Key_ResetPassword();
    g_status_dirty=1;
    OLED_Clear();
    g_state      = s;
    g_state_tick = HAL_GetTick();
    g_last_beep  = 0;

    switch (s)
    {
    case STATE_DISARMED:
        /* 撤防：停报警、关红灯、亮绿灯 */
        Alarm_Stop();
        BUZZER_OFF();
        LED_R_OFF();
        LED_G_ON();
        g_over_count = 0;
        g_gps_ready  = 0;
        Key_FlushEvents();          /* 丢掉残留按键事件，防止立刻误触发 */
        break;

    case STATE_ARMING:
        /* 开始倒计时：红灯亮、绿灯灭 */
        Alarm_Stop();
        LED_R_ON();
        LED_G_OFF();
        g_over_count = 0;
        Key_FlushEvents();
        break;

    case STATE_ARMED:
        Alarm_BeepOnce();
        LED_R_OFF(); LED_G_OFF();
        g_over_count=0;
        Key_FlushEvents();
        break;
    case STATE_FAULT:
        Alarm_Stop(); LED_R_ON(); LED_G_OFF();
        break;

    case STATE_ALARM:
        /* 立即报警 + 立即推送（把 last_report 拨回一轮前，让主循环马上推） */
        Alarm_SetLevel(ALARM_LEVEL_FULL);
        g_last_report = HAL_GetTick() - REPORT_INTERVAL_MS;
        Key_FlushEvents();
        break;

    default:
        break;
    }
}

/* ============================================================================
 *  网络推送：报警时上报状态（含 GPS 坐标）到巴法云 state001
 * ==========================================================================*/
static const char *App_StateName(void) {
    switch(g_state) {
    case STATE_DISARMED:return "disarmed";
    case STATE_ARMING:return "arming";
    case STATE_ARMED:return "armed";
    case STATE_ALARM:return "alarm";
    default:return "fault";
    }
}
static uint8_t App_PublishState(void) {
    char payload[240];
    unsigned left=(g_state==STATE_ARMING && HAL_GetTick()-g_state_tick<ARM_DELAY_MS)
        ? (unsigned)((ARM_DELAY_MS-(HAL_GetTick()-g_state_tick)+999U)/1000U):0;
    int n=snprintf(payload,sizeof(payload),
        "{\"state\":\"%s\",\"armed\":%u,\"batt\":null,\"imu\":%u,\"bootId\":%lu,\"alarm\":%u,\"eventId\":\"%lu-%lu\",\"remaining\":%u,\"ack\":\"%s\",\"result\":\"%s\"}",
        App_StateName(),g_state==STATE_ARMED||g_state==STATE_ALARM,g_sensor_ok,
        (unsigned long)g_boot_id,g_state==STATE_ALARM,(unsigned long)g_boot_id,
        (unsigned long)g_alarm_count,left,g_ack,g_ack_result);
    return n>0 && n<(int)sizeof(payload) && ESP8266_MqttPublish(TOPIC_STATE,payload)==ESP_OK;
}
static void App_ReportAlarm(void) {g_status_dirty=1;}
static void App_MqttPoll(void) {
    ESP8266_MqttPoll();
    uint32_t now=HAL_GetTick();
    uint8_t connected=ESP8266_IsConnected();
    if(connected && !g_was_connected) {g_status_dirty=1;g_last_gps_report=now-GPS_REPORT_INTERVAL_MS;}
    g_was_connected=connected;
    if(!connected) return;
    if(g_status_dirty || now-g_last_state_report>=STATE_REPORT_INTERVAL_MS) {
        if(App_PublishState()) {g_status_dirty=0;g_last_state_report=now;}
    }
    if(now-g_last_gps_report>=GPS_REPORT_INTERVAL_MS) {
        GPS_Info gps;GPS_GetInfo(&gps);char payload[128];
        if(GPS_HasFix()) snprintf(payload,sizeof(payload),
            "{\"lat\":%.6f,\"lng\":%.6f,\"fix\":1,\"coord\":\"wgs84\",\"ageMs\":%lu}",
            gps.latitude,gps.longitude,(unsigned long)(now-gps.last_fix_tick));
        else snprintf(payload,sizeof(payload),"{\"fix\":0}");
        if(ESP8266_MqttPublish(TOPIC_GPS,payload)==ESP_OK) g_last_gps_report=now;
    }
}
/* Small strict parser for our command schema: two bounded JSON strings only.
 * Rejects truncation, escapes, duplicate fields and substring commands. */
static const char *skip_space(const char *s) {while(isspace((unsigned char)*s)) s++;return s;}
static const char *json_string(const char *s,char *out,size_t size) {
    s=skip_space(s);if(*s++!='"') return NULL;size_t n=0;
    while(*s && *s!='"') {
        if((unsigned char)*s<32 || *s=='\\' || n+1>=size) return NULL;
        out[n++]=*s++;
    }
    if(*s!='"') return NULL;out[n]=0;return s+1;
}
static void App_OnMqttCmd(const char *raw) {
    char cmd[8]={0},id[33]={0},key[16],value[33];
    if(!raw) return;
    const char *p=skip_space(raw);
    if(!strcmp(p,"arm")||!strcmp(p,"disarm")) snprintf(cmd,sizeof(cmd),"%s",p);
    else {
        if(*p++!='{') return;
        uint8_t seen=0;
        for(;;) {
            p=json_string(p,key,sizeof(key));if(!p) return;
            p=skip_space(p);if(*p++!=':') return;
            p=json_string(p,value,sizeof(value));if(!p) return;
            if(!strcmp(key,"cmd") && !(seen&1)) {
                if(strlen(value)>=sizeof(cmd)) return;
                strcpy(cmd,value);seen|=1;
            } else if(!strcmp(key,"requestId") && !(seen&2)) {
                for(size_t i=0;value[i];i++) if(!isalnum((unsigned char)value[i])&&value[i]!='-'&&value[i]!='_') return;
                strcpy(id,value);seen|=2;
            } else return;
            p=skip_space(p);if(*p=='}') {p=skip_space(p+1);if(*p) return;break;}
            if(*p++!=',') return;
        }
    }
    if(strcmp(cmd,"arm") && strcmp(cmd,"disarm")) return;
    if(id[0] && !strcmp(id,g_ack)) {g_status_dirty=1;return;}
    snprintf(g_ack,sizeof(g_ack),"%s",id);
    snprintf(g_ack_result,sizeof(g_ack_result),"accepted");
    if(!strcmp(cmd,"arm")) {
        if (g_state==STATE_FAULT && !g_sensor_ok) g_sensor_ok=(MPU6050_Init(&hi2c1)==0);
        if (g_sensor_ok && (g_state==STATE_DISARMED || g_state==STATE_FAULT)) App_EnterState(STATE_ARMING);
        else if (!g_sensor_ok) snprintf(g_ack_result,sizeof(g_ack_result),"rejected");
    } else App_EnterState(STATE_DISARMED);
    if(g_state==STATE_FAULT) snprintf(g_ack_result,sizeof(g_ack_result),"rejected");
    g_status_dirty=1;
}

/* ============================================================================
 *  OLED 显示：每个状态一屏
 * ==========================================================================*/
static void App_UpdateOLED(void)
{
    switch (g_state)
    {
    case STATE_FAULT:
        OLED_PrintLine(0,0,"STATE: FAULT");
        OLED_PrintLine(0,2,"CHECK SENSOR/STORE");
        OLED_PrintLine(0,4,"PB8 TO RETRY");
        break;
    case STATE_DISARMED:
        OLED_PrintLine(0, 0, "STATE: DISARMED");
        OLED_PrintLine(0, 2, "SYSTEM READY");
        OLED_PrintLine(0, 3, "PRESS PB8 TO ARM");
        OLED_PrintLineFloat(0, 4, "DEV ", g_dbg_dev, 1, 2, "g");
        OLED_PrintLine(0, 6, GPS_HasFix() ? "GPS: FIX" : "GPS: SEARCHING");
        OLED_PrintLine(0, 7, ESP8266_IsConnected() ? "NET: ONLINE" : "NET: OFFLINE");
        break;

    case STATE_ARMING:
    {
        uint32_t elapsed = HAL_GetTick() - g_state_tick;
        uint32_t left    = (elapsed >= ARM_DELAY_MS) ? 0 : (ARM_DELAY_MS - elapsed);
        uint8_t  sec     = (uint8_t)((left + 999U) / 1000U);
        uint8_t  pct     = (uint8_t)((elapsed * 100U) / ARM_DELAY_MS);

        OLED_PrintLine(0, 0, "STATE: ARMING");
        OLED_PrintLineNum(0, 2, "ARM IN ", sec, 2, " S");
        OLED_DrawProgress(pct);                 /* 倒计时进度条（第 3 页） */
        OLED_PrintLine(0, 5, "STAND STILL...");
        OLED_PrintLine(0, 6, "PB9 TO CANCEL");
        break;
    }

    case STATE_ARMED:
        OLED_PrintLine(0, 0, "STATE: ARMED");
        OLED_PrintLine(0, 2, "MONITORING...");
        OLED_PrintLineFloat(0, 3, "DEV ", g_dbg_dev, 1, 2, "g");
        OLED_PrintLineFloat(0, 4, "TH ", THRESH_LOW, 1, 2, "g");
        OLED_PrintLineFloat(0, 5, "    ", THRESH_HIGH, 1, 2, "g");
        /* 阈值接近度条形图：dev 越大条越长，方便现场调阈值 */
        OLED_DrawProgress((g_dbg_dev >= 1.0f) ? 100U : (uint8_t)(g_dbg_dev * 100.0f));
        OLED_PrintLine(0, 6, GPS_HasFix() ? "GPS: FIX" : "GPS: SEARCHING");
        break;

    case STATE_ALARM:
    default:
        OLED_PrintLine(0, 0, "STATE: ALARM!");
        OLED_PrintLine(0, 2, "SHOCK DETECTED!");
        OLED_PrintLineFloat(0, 3, "DEV ", g_dbg_dev, 1, 2, "g");
        /* 密码进度提示：让用户知道按到第几步了 */
        switch (Key_GetPwdState()) {
        case PWD_STEP_IDLE:   OLED_PrintLine(0, 4, "PWD: _  _  _");   break;
        case PWD_STEP_GOT_9:  OLED_PrintLine(0, 4, "PWD: PB9 _  _");  break;
        case PWD_STEP_GOT_98: OLED_PrintLine(0, 4, "PWD: PB9 PB8 _"); break;
        default: break;
        }
        OLED_PrintLine(0, 5, "DISARM: PB9>PB8>PB9");
        OLED_PrintLine(0, 6, g_gps_ready ? "SENT WITH GPS" : "SENT NO GPS");
        OLED_PrintLine(0, 7, ESP8266_IsBusy() ? "MQTT SENDING.." : "REPORTED");
        break;
    }
}

/* ============================================================================
 *  时钟配置：HSE 8MHz -> PLL x9 -> 72MHz
 *    AHB = 72MHz, APB1 = 36MHz(APB1 定时器 72MHz), APB2 = 72MHz, ADC = 12MHz
 * ==========================================================================*/
void SystemClock_Config(void)
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSE;
  RCC_OscInitStruct.HSEState       = RCC_HSE_ON;
  RCC_OscInitStruct.HSEPredivValue = RCC_HSE_PREDIV_DIV1;
  RCC_OscInitStruct.HSIState       = RCC_HSI_ON;
  RCC_OscInitStruct.PLL.PLLState   = RCC_PLL_ON;
  RCC_OscInitStruct.PLL.PLLSource  = RCC_PLLSOURCE_HSE;
  RCC_OscInitStruct.PLL.PLLMUL     = RCC_PLL_MUL9;     /* 8M × 9 = 72M */
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK) {
    Error_Handler();
  }

  RCC_ClkInitStruct.ClockType      = RCC_CLOCKTYPE_HCLK | RCC_CLOCKTYPE_SYSCLK
                                   | RCC_CLOCKTYPE_PCLK1 | RCC_CLOCKTYPE_PCLK2;
  RCC_ClkInitStruct.SYSCLKSource   = RCC_SYSCLKSOURCE_PLLCLK;
  RCC_ClkInitStruct.AHBCLKDivider  = RCC_SYSCLK_DIV1;   /* HCLK  = 72M */
  RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV2;     /* PCLK1 = 36M */
  RCC_ClkInitStruct.APB2CLKDivider = RCC_HCLK_DIV1;     /* PCLK2 = 72M */
  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_2) != HAL_OK) {
    Error_Handler();
  }

  /* ★ 时钟切到 72MHz 后，必须重新配置 SysTick 到 1ms，
   *   否则 HAL_Delay 会因 LOAD 值不对而时间错乱甚至卡死。
   *   同时刷新 SystemCoreClock，供后续 HAL 各模块使用。 */
  SystemCoreClock = HAL_RCC_GetHCLKFreq();
  if (HAL_SYSTICK_Config(SystemCoreClock / 1000U) != 0) {
    Error_Handler();
  }
}

/* ============================================================================
 *  I2C1：100kHz 标准模式（I2C1 挂在 APB1 = 36MHz）
 * ==========================================================================*/
static void MX_I2C1_Init(void)
{
  hi2c1.Instance             = I2C1;
  hi2c1.Init.ClockSpeed      = 100000;
  hi2c1.Init.DutyCycle       = I2C_DUTYCYCLE_2;
  hi2c1.Init.OwnAddress1     = 0;
  hi2c1.Init.AddressingMode  = I2C_ADDRESSINGMODE_7BIT;
  hi2c1.Init.DualAddressMode = I2C_DUALADDRESS_DISABLE;
  hi2c1.Init.OwnAddress2     = 0;
  hi2c1.Init.GeneralCallMode = I2C_GENERALCALL_DISABLE;
  hi2c1.Init.NoStretchMode   = I2C_NOSTRETCH_DISABLE;
  if (HAL_I2C_Init(&hi2c1) != HAL_OK) {
    Error_Handler();
  }
}

/* ============================================================================
 *  USART1：115200-8-N-1（ESP8266-01S）
 * ==========================================================================*/
static void MX_USART1_UART_Init(void)
{
  huart1.Instance          = USART1;
  huart1.Init.BaudRate     = 115200;
  huart1.Init.WordLength   = UART_WORDLENGTH_8B;
  huart1.Init.StopBits     = UART_STOPBITS_1;
  huart1.Init.Parity       = UART_PARITY_NONE;
  huart1.Init.Mode         = UART_MODE_TX_RX;
  huart1.Init.HwFlowCtl    = UART_HWCONTROL_NONE;
  huart1.Init.OverSampling = UART_OVERSAMPLING_16;
  if (HAL_UART_Init(&huart1) != HAL_OK) {
    Error_Handler();
  }
}

/* ============================================================================
 *  USART2：9600-8-N-1（GPS）
 * ==========================================================================*/
static void MX_USART2_UART_Init(void)
{
  huart2.Instance          = USART2;
  huart2.Init.BaudRate     = GPS_BAUD;
  huart2.Init.WordLength   = UART_WORDLENGTH_8B;
  huart2.Init.StopBits     = UART_STOPBITS_1;
  huart2.Init.Parity       = UART_PARITY_NONE;
  huart2.Init.Mode         = UART_MODE_TX_RX;
  huart2.Init.HwFlowCtl    = UART_HWCONTROL_NONE;
  huart2.Init.OverSampling = UART_OVERSAMPLING_16;
  if (HAL_UART_Init(&huart2) != HAL_OK) {
    Error_Handler();
  }
}

/* ============================================================================
 *  GPIO
 *    PB0  = 蜂鸣器（输出，低电平有效，初值高 = 不响）
 *    PB12 = 红灯, PB13 = 绿灯（输出，初值低 = 灭）
 *    PB8  = 设防键, PB9 = 撤防键（输入，内部上拉，按下为低）
 * ==========================================================================*/
static void MX_GPIO_Init(void)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};

  __HAL_RCC_GPIOA_CLK_ENABLE();
  __HAL_RCC_GPIOB_CLK_ENABLE();

  /* 先写默认电平再配模式，避免上电瞬间蜂鸣器尖叫 */
  HAL_GPIO_WritePin(GPIOB, BUZZER_Pin | LED_R_Pin | LED_G_Pin, GPIO_PIN_RESET);
  HAL_GPIO_WritePin(GPIOB, BUZZER_Pin, GPIO_PIN_SET);   /* 低有效 -> 高 = 关 */

  /* --- 输出：蜂鸣器 PB0 --- */
  GPIO_InitStruct.Pin   = BUZZER_Pin;
  GPIO_InitStruct.Mode  = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull  = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(BUZZER_GPIO_Port, &GPIO_InitStruct);

  /* --- 输出：红灯 PB12 / 绿灯 PB13 --- */
  GPIO_InitStruct.Pin   = LED_R_Pin | LED_G_Pin;
  GPIO_InitStruct.Mode  = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull  = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(LED_R_GPIO_Port, &GPIO_InitStruct);

  /* --- 输入：设防键 PB8 / 撤防键 PB9，内部上拉 --- */
  GPIO_InitStruct.Pin  = KEY_ARM_Pin | KEY_DISARM_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
  GPIO_InitStruct.Pull = GPIO_PULLUP;
  HAL_GPIO_Init(KEY_ARM_GPIO_Port, &GPIO_InitStruct);
}

/* ============================================================================
 *  错误处理：红灯慢闪（现场一眼看出是初始化失败）
 * ==========================================================================*/
void Error_Handler(void)
{
  /* Keep SysTick available for fault indication. */
  while (1)
  {
      LED_R_ON();
      HAL_Delay(300);
      LED_R_OFF();
      HAL_Delay(300);
  }
}

/* ============================================================================
 *  HAL 回调
 * ==========================================================================*/

/* UART 接收完成中断：按外设分发给 ESP8266 / GPS 的环形缓冲 */
void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance == USART1) {
        ESP8266_RxCpltCallback();       /* 内部会重新使能接收 */
    } else if (huart->Instance == USART2) {
        GPS_RxCpltCallback();           /* 先把收到的字节丢进环形缓冲 */
        HAL_UART_Receive_IT(&huart2, GPS_GetRxBytePtr(), 1);   /* 再续上下一字节 */
    }
}

/* UART 错误回调：出现溢出/噪声后必须重新启动接收，否则 GPS/ESP 会永久收不到数据 */
void HAL_UART_ErrorCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance == USART1) {
        HAL_UART_Receive_IT(&huart1, ESP8266_GetRxBytePtr(), 1);
    } else if (huart->Instance == USART2) {
        HAL_UART_Receive_IT(&huart2, GPS_GetRxBytePtr(), 1);
    }
}

/* ============================================================================
 *  printf 重定向（可选）
 *  ★ USART1 上挂着 ESP8266，调试打印会打断 AT 指令交互。
 *    调试时建议临时拔掉 ESP8266，或把下面的 huart1 改成 huart2（GPS 口）。
 *    要打印浮点需在链接参数加 -u _printf_float。
 *    启用方法：把 #if 0 改成 #if 1。
 * ==========================================================================*/
#if 0
int __io_putchar(int ch)
{
    HAL_UART_Transmit(&huart1, (uint8_t *)&ch, 1, 100);
    return ch;
}
#endif

#ifdef  USE_FULL_ASSERT
void assert_failed(uint8_t *file, uint32_t line)
{
  (void)file; (void)line;
}
#endif
