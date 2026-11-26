/* Cooperative ESP-AT/MQTT driver. Only the ISR writes head; only poll writes tail.
 * No waits or HAL_Delay in the network task. All TX storage is persistent. */
#include "esp8266.h"
#include "config.h"
#include "main.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
extern UART_HandleTypeDef huart1;
#define RX_SIZE 2048U
#define PACKET_SIZE 384U
#define QUEUE_SIZE 4U
static volatile uint8_t ring[RX_SIZE], rx_byte, overflow;
static volatile uint16_t head, tail;
static uint8_t initialized, online;
static EspStatus result = ESP_ERR_NOT_INIT;
static void (*cmd_cb)(const char *);
typedef enum { BOOT, AT, ECHO, MODE, MUX, NORMAL, JOIN, CLOSE, TCP,
               PROMPT, TX_DONE, SEND_OK, CONNACK, SUBACK, READY, RETRY } Phase;
typedef enum { PK_CONNECT, PK_SUBSCRIBE, PK_PUBLISH, PK_PING } PacketKind;
static Phase phase;
static PacketKind kind;
static uint32_t phase_at, phase_timeout, ping_at, ping_sent_at;
static uint8_t ping_pending;
static uint16_t mqtt_pkt_id;
static uint8_t packet[PACKET_SIZE];
static uint16_t packet_len;
static char command[192];
static uint8_t ev_ok, ev_error, ev_prompt, ev_sent, ev_conn, ev_sub;
static char line[192];
static uint16_t line_len;
static uint32_t ipd_left, rx_at;
static uint8_t frame[PACKET_SIZE];
static uint16_t frame_len;
typedef struct { uint16_t len; uint8_t data[PACKET_SIZE]; } Queued;
static Queued queue[QUEUE_SIZE];
static uint8_t qhead, qtail, qcount;
static void fail(void);
static void enter(Phase p, uint32_t timeout) {
    phase=p; phase_at=HAL_GetTick(); phase_timeout=timeout;
}
static void clear_events(void) { ev_ok=ev_error=ev_prompt=ev_sent=0; }
static uint8_t tx(const uint8_t *data, uint16_t len) {
    return HAL_UART_Transmit_IT(&huart1,(uint8_t *)data,len)==HAL_OK;
}
static void issue(const char *s, Phase p, uint32_t timeout) {
    clear_events();
    if (s != command) snprintf(command,sizeof(command),"%s",s);
    if (!tx((uint8_t *)command,(uint16_t)strlen(command))) { fail(); return; }
    enter(p,timeout);
}
static void fail(void) {
    online=0; result=ESP_ERR_NET; ping_pending=0;
    HAL_UART_AbortTransmit(&huart1);
    frame_len=line_len=0; ipd_left=0; qhead=qtail=qcount=0;
    tail=head; overflow=0; clear_events(); ev_conn=ev_sub=0;
    enter(RETRY,5000);
}
void ESP8266_RxCpltCallback(void) {
    uint16_t next=(uint16_t)((head+1U)&(RX_SIZE-1U));
    if(next==tail) overflow=1;
    else {ring[head]=rx_byte; head=next;}
    HAL_UART_Receive_IT(&huart1,(uint8_t *)&rx_byte,1);
}
uint8_t *ESP8266_GetRxBytePtr(void) {return (uint8_t *)&rx_byte;}
static uint16_t MqttEncodeRemLen(uint32_t len, uint8_t *out)
{
    uint16_t n = 0;
    do {
        uint8_t d = (uint8_t)(len % 128);
        len /= 128;
        if (len > 0) d |= 0x80;
        out[n++] = d;
    } while (len > 0);
    return n;
}

/* 写 2 字节大端长度（MQTT 字符串前缀） */
static void MqttWriteStr(uint8_t *buf, uint16_t *pos, const char *s)
{
    uint16_t len = (uint16_t)strlen(s);
    buf[(*pos)++] = (uint8_t)(len >> 8);
    buf[(*pos)++] = (uint8_t)(len & 0xFF);
    memcpy(&buf[*pos], s, len);
    *pos += len;
}

/**
 * @brief 组装 CONNECT 报文
 * 固定头 0x10 + 剩余长度 + 协议名 + 协议级 + 连接标志 + 保活 + 载荷
 */
static uint16_t MqttBuildConnect(uint8_t *buf, const char *clientId,
                                 const char *user, const char *pass)
{
    uint8_t  var[256];
    uint16_t vp = 0;
    uint8_t  rem[4];
    uint16_t rl, pos = 0;

    MqttWriteStr(var, &vp, "MQTT");      /* 协议名 */
    var[vp++] = 0x04;                    /* 协议级别 MQTT 3.1.1 */

    /* 连接标志：用户名 + 密码 + 清理会话 */
    var[vp++] = 0xC2;

    /* 保活 60 秒 */
    var[vp++] = 0x00;
    var[vp++] = 0x3C;

    MqttWriteStr(var, &vp, clientId);    /* clientID = 私钥 */
    MqttWriteStr(var, &vp, user);        /* 用户名 = 私钥 */
    MqttWriteStr(var, &vp, pass);        /* 密码 = 123456 */

    buf[pos++] = 0x10;                   /* 报文类型 CONNECT */
    rl = MqttEncodeRemLen(vp, rem);
    memcpy(&buf[pos], rem, rl);
    pos += rl;
    memcpy(&buf[pos], var, vp);
    pos += vp;
    return pos;
}

/* 组装 SUBSCRIBE 报文 */
static uint16_t MqttBuildSubscribe(uint8_t *buf, uint16_t pktId, const char *topic)
{
    uint8_t  var[256];
    uint16_t vp = 0;
    uint8_t  rem[4];
    uint16_t rl, pos = 0;

    var[vp++] = (uint8_t)(pktId >> 8);
    var[vp++] = (uint8_t)(pktId & 0xFF);
    MqttWriteStr(var, &vp, topic);
    var[vp++] = 0x00;                    /* QoS 0 */

    buf[pos++] = 0x82;                   /* SUBSCRIBE（含固定头标志 0x2） */
    rl = MqttEncodeRemLen(vp, rem);
    memcpy(&buf[pos], rem, rl);
    pos += rl;
    memcpy(&buf[pos], var, vp);
    pos += vp;
    return pos;
}

/* 组装 PUBLISH 报文（QoS 0） */
static uint16_t MqttBuildPublish(uint8_t *buf, const char *topic, const char *payload)
{
    uint8_t  var[256];
    uint16_t vp = 0;
    uint8_t  rem[4];
    uint16_t rl, pos = 0;
    uint16_t plen = (uint16_t)strlen(payload);

    MqttWriteStr(var, &vp, topic);
    memcpy(&var[vp], payload, plen);
    vp += plen;

    buf[pos++] = 0x30;                   /* PUBLISH QoS 0 */
    rl = MqttEncodeRemLen(vp, rem);
    memcpy(&buf[pos], rem, rl);
    pos += rl;
    memcpy(&buf[pos], var, vp);
    pos += vp;
    return pos;
}

/* 组装 PINGREQ 报文（固定 2 字节） */
static uint16_t MqttBuildPingreq(uint8_t *buf)
{
    buf[0] = 0xC0;
    buf[1] = 0x00;
    return 2;
}

static void mqtt_frame(uint16_t start, uint32_t rem) {
    uint8_t type=frame[0]>>4;
    if(type==2) {
        if (kind!=PK_CONNECT || (phase!=TX_DONE && phase!=SEND_OK && phase!=CONNACK)) return;
        if(rem!=2 || frame[start]!=0 || frame[start+1]!=0) {fail();return;}
        ev_conn=1;
    } else if(type==9) {
        if (kind!=PK_SUBSCRIBE || (phase!=TX_DONE && phase!=SEND_OK && phase!=SUBACK)) return;
        if(rem!=3 || (((uint16_t)frame[start]<<8)|frame[start+1])!=mqtt_pkt_id || frame[start+2]!=0) {fail();return;}
        ev_sub=1;
    } else if(type==13 && rem==0) {ping_pending=0;}
    else if(type==3) {
        /* Subscription requests QoS0. Reject retained control commands. */
        if(!online || (frame[0]&7U)!=0 || rem<2) return;
        uint16_t tl=((uint16_t)frame[start]<<8)|frame[start+1];
        if((uint32_t)tl+2U>rem) {fail();return;}
        if(tl!=strlen(TOPIC_CMD) || memcmp(frame+start+2,TOPIC_CMD,tl)!=0) return;
        uint16_t len=(uint16_t)(rem-2U-tl);
        if(len==0 || len>=192) return;
        char payload[192]; memcpy(payload,frame+start+2+tl,len); payload[len]=0;
        if(memchr(payload,0,len)!=NULL) return;
        if(cmd_cb) cmd_cb(payload);
    }
}
static void mqtt_byte(uint8_t b) {
    if(frame_len>=sizeof(frame)) {fail();return;}
    frame[frame_len++]=b;
    if(frame_len<2) return;
    uint32_t rem=0, mult=1; uint16_t i;
    for(i=1;i<frame_len && i<=4;i++) {
        uint8_t d=frame[i]; rem+=(uint32_t)(d&127U)*mult;
        if(!(d&128U)) {
            uint32_t total=i+1U+rem;
            if(total>sizeof(frame)) {fail();return;}
            if(frame_len==total) {mqtt_frame(i+1,rem);frame_len=0;}
            return;
        }
        mult*=128U;
    }
    if(i>4) fail();
}
static void consume(uint8_t b) {
    rx_at=HAL_GetTick();
    if(ipd_left) {ipd_left--;mqtt_byte(b);return;}
    if(b=='>' && phase==PROMPT) {ev_prompt=1;line_len=0;return;}
    if(b=='\r') return;
    if(b=='\n') {
        line[line_len]=0;
        if(!strcmp(line,"OK") || !strcmp(line,"ALREADY CONNECTED")) ev_ok=1;
        if(!strcmp(line,"ERROR") || strstr(line,"FAIL") || strstr(line,"busy")) ev_error=1;
        if(!strcmp(line,"SEND OK")) ev_sent=1;
        if((strstr(line,"WIFI DISCONNECT") && (phase==TCP || online)) || (!strcmp(line,"CLOSED") && phase!=CLOSE) || (!strcmp(line,"ready") && online)) {fail();return;}
        line_len=0;return;
    }
    if(line_len>=sizeof(line)-1) {fail();return;}
    line[line_len++]=(char)b;line[line_len]=0;
    if(b==':' && line_len>5 && !strncmp(line,"+IPD,",5)) {
        uint32_t n=0;
        for(uint16_t i=5;i<line_len-1;i++) {
            if(line[i]<'0'||line[i]>'9'||n>6553) {fail();return;}
            n=n*10U+(uint32_t)(line[i]-'0');
        }
        if(n==0 || n>65535U) {fail();return;}
        ipd_left=n;line_len=0;
    }
}
static void send_packet(PacketKind k) {
    kind=k;
    snprintf(command,sizeof(command),"AT+CIPSEND=%u\r\n",(unsigned)packet_len);
    issue(command,PROMPT,2000);
}
static void connect_packet(void) {
    if(strlen(BEMFA_UID)*2U+strlen(BEMFA_PASSWORD)+16U>256U) {fail();return;}
    ev_conn=0; packet_len=MqttBuildConnect(packet,BEMFA_UID,BEMFA_UID,BEMFA_PASSWORD);
    send_packet(PK_CONNECT);
}
static void subscribe_packet(void) {
    if(strlen(TOPIC_CMD)>240U) {fail();return;}
    if(++mqtt_pkt_id==0) mqtt_pkt_id=1;
    ev_sub=0;packet_len=MqttBuildSubscribe(packet,mqtt_pkt_id,TOPIC_CMD);
    send_packet(PK_SUBSCRIBE);
}
uint8_t ESP8266_IsConnected(void) {return online;}
uint8_t ESP8266_IsBusy(void) {return phase!=READY || qcount!=0;}
EspStatus ESP8266_GetLastResult(void) {return result;}
void ESP8266_SetCmdCallback(void (*cb)(const char *)) {cmd_cb=cb;}
EspStatus ESP8266_Init(void) {
    initialized=1;online=0;head=tail=0;overflow=0;
    frame_len=line_len=0;ipd_left=0;qhead=qtail=qcount=0;
    clear_events();ev_conn=ev_sub=0;ping_pending=0;
    enter(BOOT,800);
    if(HAL_UART_Receive_IT(&huart1,(uint8_t *)&rx_byte,1)!=HAL_OK) {
        fail();
        return ESP_ERR_FAIL;
    }
    result=ESP_OK;return ESP_OK;
}
/* Compatibility calls: connection is now driven exclusively by MqttPoll. */
EspStatus ESP8266_JoinWiFi(const char *s,const char *p) {(void)s;(void)p;return initialized?ESP_OK:ESP_ERR_NOT_INIT;}
uint8_t ESP8266_CheckLink(void) {return online;}
EspStatus ESP8266_MqttConnect(void) {return online?ESP_OK:ESP_ERR_NET;}
void ESP8266_MqttDisconnect(void) {fail();}
EspStatus ESP8266_MqttPublish(const char *topic,const char *payload) {
    if(!online) return ESP_ERR_NET;
    if(!topic||!payload||strlen(topic)+strlen(payload)+2U>256U) return ESP_ERR_FAIL;
    if(qcount>=QUEUE_SIZE) return ESP_ERR_FAIL;
    queue[qhead].len=MqttBuildPublish(queue[qhead].data,topic,payload);
    qhead=(uint8_t)((qhead+1U)%QUEUE_SIZE);qcount++;
    return ESP_OK; /* queued, NOT server/application acknowledgement */
}
void ESP8266_MqttPoll(void) {
    if(!initialized) return;
    if(overflow) {fail();return;}
    uint16_t budget=512;
    while(tail!=head && budget--) {
        uint8_t b=ring[tail];tail=(uint16_t)((tail+1U)&(RX_SIZE-1U));consume(b);
    }
    uint32_t now=HAL_GetTick();
    if((ipd_left||frame_len) && (now-rx_at)>3000U) {fail();return;}
    if(ping_pending && (now-ping_sent_at)>10000U) {fail();return;}
    if(phase==BOOT || phase==RETRY) {
        if(now-phase_at>=phase_timeout) {
            /* HAL_BUSY means an existing receive is already armed. */
            HAL_UART_Receive_IT(&huart1,(uint8_t *)&rx_byte,1);
            issue("AT\r\n",AT,2000);
        }
        return;
    }
    if(phase!=READY && phase!=CLOSE && ev_error) {fail();return;}
    if(phase!=READY && now-phase_at>=phase_timeout) {
        if(phase==CLOSE) {clear_events();} else {fail();return;}
    }
    switch(phase) {
    case AT: if(ev_ok) issue("ATE0\r\n",ECHO,2000);break;
    case ECHO: if(ev_ok) issue("AT+CWMODE=1\r\n",MODE,2000);break;
    case MODE: if(ev_ok) issue("AT+CIPMUX=0\r\n",MUX,2000);break;
    case MUX: if(ev_ok) issue("AT+CIPMODE=0\r\n",NORMAL,2000);break;
    case NORMAL:
        if(ev_ok) {
            int n=snprintf(command,sizeof(command),"AT+CWJAP=\"%s\",\"%s\"\r\n",WIFI_SSID,WIFI_PASSWORD);
            if(n<0 || n>=(int)sizeof(command)) {fail();break;}
            issue(command,JOIN,20000);
        }break;
    case JOIN: if(ev_ok) issue("AT+CIPCLOSE\r\n",CLOSE,1500);break;
    case CLOSE:
        if(ev_ok||ev_error||now-phase_at>=phase_timeout) {
            snprintf(command,sizeof(command),"AT+CIPSTART=\"TCP\",\"%s\",%u\r\n",BEMFA_MQTT_HOST,BEMFA_MQTT_PORT);
            issue(command,TCP,12000);
        }break;
    case TCP: if(ev_ok) connect_packet();break;
    case PROMPT:
        if(ev_prompt) {
            ev_sent=0;
            if(!tx(packet,packet_len)) {fail();break;}
            enter(TX_DONE,2000);
        }break;
    case TX_DONE: if(huart1.gState==HAL_UART_STATE_READY) enter(SEND_OK,8000);break;
    case SEND_OK:
        if(ev_sent) {
            if(kind==PK_CONNECT) enter(CONNACK,8000);
            else if(kind==PK_SUBSCRIBE) enter(SUBACK,8000);
            else {result=ESP_OK;enter(READY,0);}
        }break;
    case CONNACK: if(ev_conn) subscribe_packet();break;
    case SUBACK:
        if(ev_sub) {online=1;result=ESP_OK;ping_at=now;enter(READY,0);}break;
    case READY:
        if(now-ping_at>=MQTT_ALIVE_INTERVAL_MS) {
            ping_at=ping_sent_at=now;ping_pending=1;packet_len=MqttBuildPingreq(packet);send_packet(PK_PING);
        } else if(qcount) {
            packet_len=queue[qtail].len;memcpy(packet,queue[qtail].data,packet_len);
            qtail=(uint8_t)((qtail+1U)%QUEUE_SIZE);qcount--;send_packet(PK_PUBLISH);
        }break;
    default: break;
    }
}
