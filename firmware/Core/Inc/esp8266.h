/**
  ******************************************************************************
  * @file    esp8266.h
  * @brief   ESP8266-01S 巴法云 MQTT 客户端（TCP 透传 + 手拼 MQTT 报文）
  * @note    只用最基础 AT 指令（AT / AT+CWMODE / AT+CWJAP / AT+CIPSTART /
  *          AT+CIPSEND），适配 AT 固件 1.x / 2.x / 3.x。
  *          MQTT 报文（CONNECT/SUBSCRIBE/PUBLISH/PINGREQ）由本模块在 MCU 侧
  *          手动拼装成字节流，通过 AT+CIPSEND 透传发给巴法云。
  ******************************************************************************
  */

#ifndef __ESP8266_H
#define __ESP8266_H

#include "stm32f1xx_hal.h"

/* 返回码 */
typedef enum {
    ESP_OK           = 0,
    ESP_ERR_TIMEOUT  = 1,
    ESP_ERR_FAIL     = 2,      /* 收到 ERROR / FAIL */
    ESP_ERR_NOT_INIT = 3,
    ESP_ERR_NET      = 4       /* 网络/MQTT 层失败 */
} EspStatus;

/* 初始化：清状态 + 探测模块（发 AT，有 OK 才算在线） */
EspStatus ESP8266_Init(void);

/* 是否已连上 WiFi */
uint8_t ESP8266_IsConnected(void);

/* 连接 WiFi（阻塞，最长 ESP_JOIN_TIMEOUT_MS） */
EspStatus ESP8266_JoinWiFi(const char *ssid, const char *pass);

/* 查询 WiFi 连接状态（AT+CIPSTATUS），1 = 已连上 */
uint8_t ESP8266_CheckLink(void);

/* ====================== MQTT 接口 ====================== */

/**
 * @brief 建立巴法云 MQTT 会话：TCP 连接 + CONNECT + 订阅 cmd001
 * @note  调用前必须先 JoinWiFi 成功。内部会做完整握手。
 */
EspStatus ESP8266_MqttConnect(void);

/* 断开 MQTT / TCP（掉线重连前调用） */
void ESP8266_MqttDisconnect(void);

/**
 * @brief 发布消息到指定主题
 * @param topic  主题名，如 "state001"
 * @param payload 消息体（JSON 字符串），长度 < 256
 * @retval ESP_OK 成功
 */
EspStatus ESP8266_MqttPublish(const char *topic, const char *payload);

/**
 * @brief 主循环轮询：处理收到的 MQTT 数据（含 PINGRESP / PUBLISH）
 * @note  每 10ms 调用一次即可，内部非阻塞。
 *        收到 cmd001 的 arm/disarm 会通过回调通知上层。
 */
void ESP8266_MqttPoll(void);

/**
 * @brief 设置「收到订阅命令」回调
 * @param cb 参数为命令字符串，如 "arm" / "disarm"（或 JSON 原文）
 */
void ESP8266_SetCmdCallback(void (*cb)(const char *cmd));

/* 是否正在执行阻塞操作（主循环据此显示状态） */
uint8_t ESP8266_IsBusy(void);

/* 最近一次操作结果（ESP_OK = 成功） */
EspStatus ESP8266_GetLastResult(void);

/* 中断相关（供 main.c 的 HAL 回调使用） */
void     ESP8266_RxCpltCallback(void);
uint8_t *ESP8266_GetRxBytePtr(void);

#endif /* __ESP8266_H */
