/**
  ******************************************************************************
  * @file    gps.h
  * @brief   GPS NMEA 解析：只取 $GPGGA / $GNGGA 的经纬度、定位质量、卫星数
  ******************************************************************************
  */

#ifndef __GPS_H
#define __GPS_H

#include "stm32f1xx_hal.h"

typedef struct {
    uint8_t  valid;          /* 1 = 已定位（GGA 定位质量为 1 或 2） */
    uint8_t  sats;           /* 卫星数 */
    uint8_t  fixQuality;     /* 0=无效 1=GPS 2=差分 */
    double   latitude;       /* 十进制度，北纬为正，如 31.230416 */
    double   longitude;      /* 十进制度，东经为正，如 121.473701 */
    uint32_t last_fix_tick;  /* 最后一次有效定位的时间戳 */
} GPS_Info;

/* 初始化并启动 USART2 中断接收 */
void GPS_Init(void);

/* 中断完成回调（main.c 的 HAL_UART_RxCpltCallback 调用） */
void GPS_RxCpltCallback(void);

/* 取内部 1 字节接收缓冲指针（重新使能中断接收用） */
uint8_t *GPS_GetRxBytePtr(void);

/* 主循环调用：解析环形缓冲里的字节，找到 GGA 就更新定位信息 */
void GPS_Task(void);

/* 取最新定位（拷贝快照） */
void GPS_GetInfo(GPS_Info *out);

/* 当前是否有可用定位（GPS_FIX_TIMEOUT_MS 内有有效 GGA） */
uint8_t GPS_HasFix(void);

/* 取最后一行原始 NMEA（调试用） */
uint8_t GPS_GetDebugLine(char *buf, uint16_t maxLen);

#endif /* __GPS_H */
