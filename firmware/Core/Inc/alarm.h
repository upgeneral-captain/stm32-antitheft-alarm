/**
  ******************************************************************************
  * @file    alarm.h
  * @brief   蜂鸣器 / 红灯 分级报警驱动（只负责“怎么响”，不含业务状态机）
  * @note    main.c 的状态机决定“要不要响、响哪一级”，
  *          本模块由 Alarm_Tick() 每 10ms 推进节奏，全程非阻塞。
  ******************************************************************************
  */

#ifndef __ALARM_H
#define __ALARM_H

#include "stm32f1xx_hal.h"

typedef enum {
    ALARM_LEVEL_NONE = 0,   /* 静音 */
    ALARM_LEVEL_NOTIFY,     /* 低级别：短促“嘀-嘀” */
    ALARM_LEVEL_FULL        /* 高级别：连续高分贝 + 红灯闪 */
} AlarmLevel;

void Alarm_Init(void);

/* 设置级别（主循环可随时调用；级别未变时节奏继续，不打断） */
void Alarm_SetLevel(AlarmLevel level);
AlarmLevel Alarm_GetLevel(void);

/* 每 10ms 调一次，推进节奏（内部无 while 等待） */
void Alarm_Tick(void);

/* 立即静音 + 灭灯 */
void Alarm_Stop(void);

/* 单发一声“嘀”（设防倒计时/布防成功提示用） */
void Alarm_BeepOnce(void);

#endif /* __ALARM_H */
