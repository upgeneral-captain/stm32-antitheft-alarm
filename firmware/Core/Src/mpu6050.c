/**
  ******************************************************************************
  * @file    mpu6050.c
  * @brief   MPU6050 驱动：初始化、读加速度、计算震动偏差
  *
  * 判定思路（重要）：
  *   静止或倾斜时，合加速度 |a| 恒等于 1g（重力大小不变）；
  *   只有真正的“运动 / 撞击 / 被搬走”才会让 |a| 突然变大或变小。
  *   所以用  dev = | |a| - ref |  作为震动强度，天然抗“姿态变化”，
  *   不会因为设备被摆歪了就误报——这是防误报的第一层。
  ******************************************************************************
  */

#include "mpu6050.h"
#include "config.h"
#include "math.h"

/* ========================== 寄存器 ========================== */
#define MPU_REG_SMPLRT_DIV      0x19
#define MPU_REG_CONFIG          0x1A
#define MPU_REG_GYRO_CONFIG     0x1B
#define MPU_REG_ACCEL_CONFIG    0x1C
#define MPU_REG_ACCEL_XOUT_H    0x3B
#define MPU_REG_PWR_MGMT_1      0x6B
#define MPU_REG_PWR_MGMT_2      0x6C
#define MPU_REG_WHO_AM_I        0x75

#define MPU_SCALE_2G            16384.0f   /* ±2g：16384 LSB = 1g */

/* ========================== 内部状态 ========================== */
static I2C_HandleTypeDef *mpu_i2c = NULL;
static uint8_t mpu_online = 0;      /* 1 = 通信正常 */
static float   ref_mag    = 1.0f;   /* 静止基准合加速度 */
static float   last_mag   = 0.0f;   /* 最近一次合加速度 */

/* ========================== 底层读写 ========================== */

static uint8_t MPU_WriteReg(uint8_t reg, uint8_t val)
{
    uint8_t buf[2];
    buf[0] = reg;
    buf[1] = val;
    if (HAL_I2C_Master_Transmit(mpu_i2c, MPU6050_ADDR, buf, 2, 3) != HAL_OK) {
        mpu_online = 0;
        return 1;
    }
    mpu_online = 1;
    return 0;
}

static uint8_t MPU_ReadRegs(uint8_t reg, uint8_t *buf, uint16_t len)
{
    if (HAL_I2C_Mem_Read(mpu_i2c, MPU6050_ADDR, reg, I2C_MEMADD_SIZE_8BIT,
                         buf, len, 3) != HAL_OK) {
        mpu_online = 0;
        return 1;
    }
    mpu_online = 1;
    return 0;
}

/* ========================== 公开接口 ========================== */

uint8_t MPU6050_IsOnline(void)     { return mpu_online; }
float   MPU6050_GetDebugMag(void)  { return last_mag; }
float   MPU6050_GetRefMag(void)    { return ref_mag; }

/**
 * @brief 初始化 MPU6050
 */
uint8_t MPU6050_Init(I2C_HandleTypeDef *hi2c)
{
    uint8_t who = 0;

    mpu_i2c    = hi2c;
    mpu_online = 0;

    HAL_Delay(50);                                  /* 上电稳定 */

    /* 1. 复位 */
    if (MPU_WriteReg(MPU_REG_PWR_MGMT_1, 0x80) != 0) return 1;
    HAL_Delay(100);

    /* 2. 唤醒，时钟用内部 X 轴陀螺 PLL（比 8M RC 稳） */
    if (MPU_WriteReg(MPU_REG_PWR_MGMT_1, 0x01) != 0) return 1;
    HAL_Delay(10);

    /* 3. 全部轴唤醒 */
    if (MPU_WriteReg(MPU_REG_PWR_MGMT_2, 0x00) != 0) return 1;

    /* GY-521 uses an MPU6050; 0x68 is WHO_AM_I regardless of AD0. */
    if (MPU_ReadRegs(MPU_REG_WHO_AM_I, &who, 1) || who != 0x68) {
        mpu_online=0;
        return 1;
    }

    /* 5. 采样率 100Hz：SMPLRT_DIV = 9 -> 1kHz/(1+9) = 100Hz（10ms 一次，正好匹配需求） */
    if (MPU_WriteReg(MPU_REG_SMPLRT_DIV, 9) != 0) return 1;

    /* 6. DLPF 44Hz 低通：滤掉电机/风扇/路面高频抖动（防误报第二层） */
    if (MPU_WriteReg(MPU_REG_CONFIG, 0x03) != 0) return 1;

    /* 7. 陀螺 ±500dps（不用），加速度 ±2g（ACCEL_CONFIG=0x00） */
    if (MPU_WriteReg(MPU_REG_GYRO_CONFIG, 0x08) != 0) return 1;
    if (MPU_WriteReg(MPU_REG_ACCEL_CONFIG, 0x00) != 0) return 1;

    HAL_Delay(50);

    /* 8. 校准静止基准 */
    MPU6050_Calibrate();

    return mpu_online ? 0 : 1;
}

uint8_t MPU6050_ReadRaw(MPU6050_Raw *raw)
{
    uint8_t buf[6];

    if (MPU_ReadRegs(MPU_REG_ACCEL_XOUT_H, buf, 6) != 0) {
        return 1;
    }
    /* 高字节在前，有符号 */
    raw->ax = (int16_t)(((uint16_t)buf[0] << 8) | buf[1]);
    raw->ay = (int16_t)(((uint16_t)buf[2] << 8) | buf[3]);
    raw->az = (int16_t)(((uint16_t)buf[4] << 8) | buf[5]);
    return 0;
}

uint8_t MPU6050_ReadAccel(MPU6050_Accel *acc)
{
    MPU6050_Raw r;

    if (MPU6050_ReadRaw(&r) != 0) return 1;

    acc->ax = (float)r.ax / MPU_SCALE_2G;
    acc->ay = (float)r.ay / MPU_SCALE_2G;
    acc->az = (float)r.az / MPU_SCALE_2G;
    return 0;
}

float MPU6050_GetMagnitude(void)
{
    MPU6050_Accel a;

    if (MPU6050_ReadAccel(&a) != 0) {
        return last_mag;        /* 读失败沿用上次值，不制造假报警 */
    }
    last_mag = sqrtf(a.ax * a.ax + a.ay * a.ay + a.az * a.az);
    return last_mag;
}

float MPU6050_GetDeviation(void)
{
    float mag;
    float dev;

    mag = MPU6050_GetMagnitude();

    if (!mpu_online) {
        return 0.0f;            /* 传感器掉线 -> 不报警（宁可漏报不乱报） */
    }

    dev = mag - ref_mag;
    if (dev < 0.0f) dev = -dev; /* 取绝对值：加速度变大（撞击）或变小（自由落体）都算 */

    return dev;
}

/**
 * @brief 校准静止基准
 * @note  连续采 100 点，约 1s；只统计成功读取的数据。校准时设备应静止放平。
 *        如果算出的基准离 1g 太远（说明校准时有人在动），退回理论值 1.0g。
 */
void MPU6050_Calibrate(void)
{
    float    sum = 0.0f;
    float    mag;
    uint16_t count=0;
    for (uint16_t i=0; i<MPU_CALIB_SAMPLES; i++) {
        mag = MPU6050_GetMagnitude();
        if (mpu_online) {sum+=mag; count++;}
        HAL_Delay(10);
    }
    if (count < MPU_CALIB_SAMPLES - MPU_CALIB_SAMPLES/10U) {
        mpu_online=0;
        return;
    }
    mpu_online=1;
    ref_mag = sum / (float)count;

    if (ref_mag < 0.7f || ref_mag > 1.3f) {
        ref_mag = MPU_REF_G;    /* 校准失败兜底 */
    }
}
