/**
  ******************************************************************************
  * @file    oled.h
  * @brief   SSD1306 OLED (128x64, I2C1) 驱动 + 5x7 英文字库 + 简单绘图
  ******************************************************************************
  */

#ifndef __OLED_H
#define __OLED_H

#include "stm32f1xx_hal.h"

#define OLED_I2C_ADDR      0x78U    /* SSD1306 默认地址（8 位写地址 = 0x3C<<1） */
#define OLED_WIDTH         128U
#define OLED_HEIGHT        64U

/* 初始化 + 清屏 */
void OLED_Init(I2C_HandleTypeDef *hi2c);
void OLED_Clear(void);
void OLED_Task(void);

/* 光标：x = 列（0~127 像素），y = 行（0~7，每行 8 像素） */
void OLED_SetCursor(uint8_t x, uint8_t y);

/* 单行字符串（覆盖光标所在行的全部内容，不会累加残影） */
void OLED_PrintLine(uint8_t x, uint8_t line, const char *str);

/* 单行字符串 + 浮点数，例如 OLED_PrintLineFloat(0, 2, "DEV ", dev, 1, 2, "g") */
void OLED_PrintLineFloat(uint8_t x, uint8_t line, const char *head,
                         float val, uint8_t intDigits, uint8_t fracDigits,
                         const char *tail);

/* 单行字符串 + 整数 */
void OLED_PrintLineNum(uint8_t x, uint8_t line, const char *head,
                       uint16_t num, uint8_t width, const char *tail);

/* 进度条（0~100%），画在第 3 页（y=24~31） */
void OLED_DrawProgress(uint8_t percent);

/* 最近一次 I2C 通信是否成功（1 = 正常） */
uint8_t OLED_IsOK(void);

#endif /* __OLED_H */
