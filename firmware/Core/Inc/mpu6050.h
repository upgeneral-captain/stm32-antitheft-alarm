/**
  ******************************************************************************
  * @file    mpu6050.h
  * @brief   MPU6050 驱动（只用加速度，±2g）
  ******************************************************************************
  */

#ifndef __MPU6050_H
#define __MPU6050_H

#include "stm32f1xx_hal.h"

/* 三轴原始数据（LSB，±2g 下 16384 LSB = 1g） */
typedef struct {
    int16_t ax;
    int16_t ay;
    int16_t az;
} MPU6050_Raw;

/* 三轴加速度（单位 g） */
typedef struct {
    float ax;
    float ay;
    float az;
} MPU6050_Accel;

/**
 * @brief 初始化：复位 -> 唤醒 -> ±2g -> DLPF -> 100Hz，并做静止基准校准
 * @retval 0 成功；1 找不到器件（查 PB6/PB7、供电、AD0 电平）
 * @note  初始化和校准时设备必须静止放平，否则基准会偏、开箱就误报
 */
uint8_t MPU6050_Init(I2C_HandleTypeDef *hi2c);

uint8_t MPU6050_ReadRaw(MPU6050_Raw *raw);
uint8_t MPU6050_ReadAccel(MPU6050_Accel *acc);

/* 合加速度 |a| = sqrt(ax²+ay²+az²)，单位 g */
float MPU6050_GetMagnitude(void);

/**
 * @brief 震动偏差 = | |a| - 静止基准 |，单位 g
 *        main.c 拿这个值和 THRESH_LOW / THRESH_HIGH 比较。
 *        倾斜不报警（倾斜时 |a| 仍是 1g），只有真正的运动/撞击才报警。
 */
float MPU6050_GetDeviation(void);

/* 最近一次合加速度（给 OLED 调试显示） */
float MPU6050_GetDebugMag(void);

/* 最近一次静止基准（上电校准得到的 |a|） */
float MPU6050_GetRefMag(void);

/* 重新校准静止基准（进入 ARMED 前会调用一次） */
void MPU6050_Calibrate(void);

/* 器件是否在线 */
uint8_t MPU6050_IsOnline(void);

#endif /* __MPU6050_H */
