/**
  ******************************************************************************
  * @file    stm32f1xx_hal_msp.c
  * @brief   HAL MSP：各外设的底层引脚 / 时钟 / NVIC 初始化
  * @note    手工补全（等价于 CubeMX 根据 .ioc 生成的版本）。
  *          I2C1  : PB6=SCL, PB7=SDA（复用开漏）
  *          USART1: PA9=TX, PA10=RX（接 ESP8266-01S，115200）
  *          USART2: PA2=TX, PA3=RX（接 GPS，9600）
  ******************************************************************************
  */

#include "main.h"

void HAL_MspInit(void)
{
  __HAL_RCC_AFIO_CLK_ENABLE();
  __HAL_RCC_PWR_CLK_ENABLE();
}

/* ============================== I2C1 ============================== */
void HAL_I2C_MspInit(I2C_HandleTypeDef *hi2c)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};

  if (hi2c->Instance == I2C1) {
    __HAL_RCC_GPIOB_CLK_ENABLE();

    /* PB6 -> SCL, PB7 -> SDA：复用 + 开漏 + 内部上拉
     * （模块上一般已有 4.7k 上拉；若没有，靠内部上拉在 100kHz 下也能跑） */
    GPIO_InitStruct.Pin   = GPIO_PIN_6 | GPIO_PIN_7;
    GPIO_InitStruct.Mode  = GPIO_MODE_AF_OD;
    GPIO_InitStruct.Pull  = GPIO_PULLUP;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_HIGH;
    HAL_GPIO_Init(GPIOB, &GPIO_InitStruct);

    __HAL_RCC_I2C1_CLK_ENABLE();
    /* F1 的 I2C 有著名的 errata（总线忙死锁），上电复位一次更稳 */
    __HAL_RCC_I2C1_FORCE_RESET();
    __HAL_RCC_I2C1_RELEASE_RESET();
  }
}

void HAL_I2C_MspDeInit(I2C_HandleTypeDef *hi2c)
{
  if (hi2c->Instance == I2C1) {
    __HAL_RCC_I2C1_CLK_DISABLE();
    HAL_GPIO_DeInit(GPIOB, GPIO_PIN_6 | GPIO_PIN_7);
  }
}

/* ============================== USART1 / USART2 ============================== */
void HAL_UART_MspInit(UART_HandleTypeDef *huart)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};

  if (huart->Instance == USART1) {
    __HAL_RCC_USART1_CLK_ENABLE();
    __HAL_RCC_GPIOA_CLK_ENABLE();

    /* PA9  = TX（复用推挽输出） */
    GPIO_InitStruct.Pin   = GPIO_PIN_9;
    GPIO_InitStruct.Mode  = GPIO_MODE_AF_PP;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_HIGH;
    HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);

    /* PA10 = RX（浮空输入；ESP 的 TX 是推挽，无需上拉） */
    GPIO_InitStruct.Pin  = GPIO_PIN_10;
    GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
    GPIO_InitStruct.Pull = GPIO_NOPULL;
    HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);

    /* 接收中断：优先级 1（高于 SysTick 的 15，避免 115200 丢字节） */
    HAL_NVIC_SetPriority(USART1_IRQn, 1, 0);
    HAL_NVIC_EnableIRQ(USART1_IRQn);
  }
  else if (huart->Instance == USART2) {
    __HAL_RCC_USART2_CLK_ENABLE();
    __HAL_RCC_GPIOA_CLK_ENABLE();

    /* PA2 = TX, PA3 = RX */
    GPIO_InitStruct.Pin   = GPIO_PIN_2;
    GPIO_InitStruct.Mode  = GPIO_MODE_AF_PP;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_HIGH;
    HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);

    GPIO_InitStruct.Pin  = GPIO_PIN_3;
    GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
    GPIO_InitStruct.Pull = GPIO_NOPULL;
    HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);

    HAL_NVIC_SetPriority(USART2_IRQn, 2, 0);
    HAL_NVIC_EnableIRQ(USART2_IRQn);
  }
}

void HAL_UART_MspDeInit(UART_HandleTypeDef *huart)
{
  if (huart->Instance == USART1) {
    __HAL_RCC_USART1_CLK_DISABLE();
    HAL_GPIO_DeInit(GPIOA, GPIO_PIN_9 | GPIO_PIN_10);
    HAL_NVIC_DisableIRQ(USART1_IRQn);
  }
  else if (huart->Instance == USART2) {
    __HAL_RCC_USART2_CLK_DISABLE();
    HAL_GPIO_DeInit(GPIOA, GPIO_PIN_2 | GPIO_PIN_3);
    HAL_NVIC_DisableIRQ(USART2_IRQn);
  }
}
