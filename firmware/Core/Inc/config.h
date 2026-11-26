/**
  ******************************************************************************
  * @file    config.h
  * @brief   智能防丢防盗震动报警器 —— 全部可调参数集中在此文件
  * @note    ★ 现场调试只需要改这个文件里的宏，不要到各 .c 里找魔法数字。
  *          时间单位：ms；加速度单位：g（1g = 9.80665 m/s^2）
  ******************************************************************************
  */

#ifndef __CONFIG_H
#define __CONFIG_H

/* ============================ 一、设防 / 报警时间 ============================ */
/* 设防延时：按设防键后倒计时多少秒才真正进入 ARMED（给自己留出门时间） */
#define ARM_DELAY_MS            10000U

/* 报警判定：连续多少次采样超阈值才真正报警（10ms 采样 -> 10 次 = 100ms） */
#define ALARM_CONFIRM_COUNT     10U

/* 分级提示音（THRESH_LOW ~ THRESH_HIGH 之间）每轮“嘀-嘀”的周期 */
#define NOTIFY_PERIOD_MS        3000U

/* ALARM 状态下，重复推送网络告警的间隔（需求：60 秒一次） */
#define REPORT_INTERVAL_MS      60000U

/* ============================ 二、MPU6050 阈值 ============================ */
/*
 * 判定使用“合加速度偏差”：
 *     dev = | |a| - 1g |
 * 静止/倾斜时合加速度恒为 1g，只有真正的运动、撞击才会让 |a| 偏离 1g。
 *
 * ±2g 量程下 LSB = 16384 LSB/g：
 *   0.15g ≈ 2458 LSB  —— 一般人走过带起的轻微晃动
 *   0.50g ≈ 8192 LSB  —— 明显晃动 / 拿起 / 搬动
 *   0.80g ≈ 13107 LSB —— 猛烈敲击 / 撞击 / 搬走
 */
#define THRESH_LOW              0.15f    /* 超此值 -> 短促“嘀-嘀”提示 */
#define THRESH_HIGH             0.80f    /* 超此值 -> 连续高分贝报警 */

/* 采样周期（main 里用 HAL_GetTick 判断，自然就是 10ms） */
#define MPU_SAMPLE_PERIOD_MS    10U

/* MPU6050 I2C 从机地址：AD0 接地 = 0xD0（8 位写地址），接 VCC = 0xD2 */
#define MPU6050_ADDR            0xD0U

/* 静止基准校准采样点数（上电时采 100 点求平均，约 500ms） */
#define MPU_CALIB_SAMPLES       100U

/* 校准结果不合理时的兜底基准（理论 1g） */
#define MPU_REF_G               1.0f

/* ============================ 三、按键 / 密码 ============================ */
#define KEY_DEBOUNCE_MS         10U      /* 按键软件消抖 10ms */
#define KEY_LONG_PRESS_MS       2000U    /* 长按判定：ALARM 下长按撤防键 2s 强制撤防 */
#define PASSWORD_STEP_TIMEOUT_MS 3000U   /* 撤防密码每一步必须在 3 秒内完成 */

/* ============================ 四、OLED / 蜂鸣器 / LED ============================ */
/* 蜂鸣器为低电平有效：写 0 响 */
#define BUZZER_ON()             HAL_GPIO_WritePin(GPIOB, GPIO_PIN_0, GPIO_PIN_RESET)
#define BUZZER_OFF()            HAL_GPIO_WritePin(GPIOB, GPIO_PIN_0, GPIO_PIN_SET)

/* 红灯/绿灯：写 1 点亮 */
#define LED_R_ON()              HAL_GPIO_WritePin(GPIOB, GPIO_PIN_12, GPIO_PIN_SET)
#define LED_R_OFF()             HAL_GPIO_WritePin(GPIOB, GPIO_PIN_12, GPIO_PIN_RESET)
#define LED_G_ON()              HAL_GPIO_WritePin(GPIOB, GPIO_PIN_13, GPIO_PIN_SET)
#define LED_G_OFF()             HAL_GPIO_WritePin(GPIOB, GPIO_PIN_13, GPIO_PIN_RESET)

/* 提示音 / 报警音节奏 */
#define NOTIFY_BEEP_ON_MS       100U     /* 一声“嘀”的时长 */
#define NOTIFY_BEEP_OFF_MS      150U     /* “嘀-嘀”中间停顿 */
#define NOTIFY_BEEP_COUNT       2U       /* 一轮响几声 */
#define ALARM_BEEP_ON_MS        500U     /* 报警连续音：响 0.5s */
#define ALARM_BEEP_OFF_MS       100U     /* 停 0.1s，相当于 80% 占空的高分贝急call */
#define ALARM_LED_BLINK_MS      250U     /* 红灯闪烁半周期 */

/* ============================ 五、ESP8266 / 巴法云 MQTT ============================ */
#define WIFI_SSID               "CHANGE_ME_WIFI"
#define WIFI_PASSWORD           "CHANGE_ME_WIFI_PASSWORD"

/* ---- 巴法云 MQTT ----
 * 巴法云规则：clientID = 用户名 = 私钥；密码固定 123456。
 * 服务器 bemfa.com，TCP 端口 9501。
 */
#define BEMFA_MQTT_HOST         "bemfa.com"
#define BEMFA_MQTT_PORT         9501
#define BEMFA_UID               "CHANGE_ME_BEMFA_UID"
#define BEMFA_PASSWORD          "CHANGE_ME_MQTT_PASSWORD"

/* 三个主题（与手机 App 完全一致） */
#define TOPIC_GPS               "gps001"    /* 上报经纬度 */
#define TOPIC_STATE             "state001"  /* 上报状态（设防/电量） */
#define TOPIC_CMD               "cmd001"    /* 订阅：App 下发 arm/disarm */

/* 周期性上报间隔（毫秒） */
#define STATE_REPORT_INTERVAL_MS  15000U   /* 状态心跳：15 秒一次 */
#define GPS_REPORT_INTERVAL_MS    10000U   /* 定位上报：10 秒一次 */
#define MQTT_ALIVE_INTERVAL_MS    30000U   /* MQTT 保活 ping：30 秒一次 */

/* 超时与重试 */
#define ESP_CMD_TIMEOUT_MS      1000U
#define ESP_JOIN_TIMEOUT_MS     15000U   /* 连 WiFi 最长等待 */
#define ESP_MQTT_TIMEOUT_MS     8000U    /* MQTT 操作最长等待 */
#define ESP_RETRY_TIMES         3U       /* 单条指令/整体操作重试次数 */

/* ============================ 六、GPS ============================ */
#define GPS_BAUD                9600U
#define GPS_FIX_TIMEOUT_MS      5000U    /* 超过 5s 没收到有效 GGA 就认为没信号 */

#endif /* __CONFIG_H */
