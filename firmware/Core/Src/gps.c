/**
  ******************************************************************************
  * @file    gps.c
  * @brief   NMEA-0183 $GPGGA 解析（USART2 中断逐字节接收 + 主循环组帧解析）
  *
  * 数据流：
  *   USART2 RX 中断 -> 环形缓冲 256B -> GPS_Task() 取字节 -> 按 CR/LF 切行
  *   -> 只处理含 "GGA" 的行 -> 解析经纬度 -> 更新 GPS_Info
  *
  * 为什么不在中断里解析：中断里做字符串/浮点运算会拉长中断时间，导致丢字节。
  ******************************************************************************
  */

#include "gps.h"
#include "config.h"
#include "main.h"
#include <string.h>
#include <stdlib.h>

extern UART_HandleTypeDef huart2;

/* ====================== 环形缓冲 ====================== */
#define GPS_RING_SIZE   256U        /* 必须是 2 的幂 */

static volatile uint8_t  rx_ring[GPS_RING_SIZE];
static volatile uint16_t rx_head = 0;      /* 中断写 */
static volatile uint16_t rx_tail = 0;      /* 主循环读 */
static volatile uint8_t  rx_byte;

/* ====================== 行缓冲 ====================== */
#define GPS_LINE_SIZE   100U

static char     line_buf[GPS_LINE_SIZE];
static uint16_t line_len = 0;

/* ====================== 结果 ====================== */
static GPS_Info gps_info;         /* 解析器写 */
static GPS_Info gps_snapshot;     /* 给主循环读的快照 */
static char     last_line[GPS_LINE_SIZE];

/* ====================== 内部工具 ====================== */

static void RingPush(uint8_t b)
{
    uint16_t next = (uint16_t)((rx_head + 1) & (GPS_RING_SIZE - 1));
    if (next == rx_tail) {
        return; /* ISR never modifies consumer index. Discard damaged line by checksum. */
    }
    rx_ring[rx_head] = b;
    rx_head = next;
}

static uint8_t RingPop(uint8_t *b)
{
    if (rx_tail == rx_head) return 0;
    *b = rx_ring[rx_tail];
    rx_tail = (uint16_t)((rx_tail + 1) & (GPS_RING_SIZE - 1));
    return 1;
}

/**
 * @brief NMEA 的“度分”格式转十进制度
 *        例：3113.8250 + 'N' -> 31 + 13.8250/60 = 31.230416°
 * @note 用整数拆位后再算，比整串 atof 更稳（也不受 locale 影响）
 */
static uint8_t NmeaToDegrees(const char *p, unsigned deg_digits, char hemi, double *out)
{
    unsigned deg=0, min=0;
    for (unsigned i=0; i<deg_digits+2U; i++) {
        if (*p<'0' || *p>'9') return 0;
        if (i<deg_digits) deg=10U*deg+(unsigned)(*p-'0');
        else min=10U*min+(unsigned)(*p-'0');
        p++;
    }
    double frac=0.0, factor=0.1;
    if (*p=='.') {
        p++;
        if (*p<'0' || *p>'9') return 0;
        while (*p>='0' && *p<='9') {
            frac+=factor*(*p++-'0'); factor*=0.1;
        }
    }
    unsigned max=deg_digits==2 ? 90U : 180U;
    if (*p!=',' || min>=60U || deg>max || (deg==max && (min || frac>0.0))) return 0;
    double result=deg+(min+frac)/60.0;
    *out=(hemi=='S'||hemi=='W') ? -result : result;
    return 1;
}

/* 取第 n 个逗号之后的字段起点（n 从 0 开始，0 = 语句头） */
static char *NmeaField(char *s, uint8_t n)
{
    char   *p = s;
    uint8_t i;

    /* 跳过语句头到第一个逗号 */
    for (i = 0; i < n; i++) {
        p = strchr(p, ',');
        if (p == NULL) return NULL;
        p++;
    }
    return p;
}

/**
 * @brief 解析一行 GGA
 * $GPGGA,hhmmss.ss,llll.ll,a,yyyyy.yy,a,q,ss,h.h,alt,M,sep,M,dgps,ref*hh
 *   字段: 0=头 1=UTC 2=纬度 3=N/S 4=经度 5=E/W 6=质量 7=卫星数 8=HDOP ...
 */
static void ParseGGA(char *line)
{
    char   *f;
    char   *lat_str;
    char   *lon_str;
    char    hemi_lat;
    char    hemi_lon;
    uint8_t quality;
    uint8_t sats;

    /* Validate full NMEA frame before accepting any position. */
    f = strchr(line, '*');
    if(!f || strlen(f)!=3) return;
    unsigned checksum=0;for(char *p=line+1;p<f;p++) checksum^=(unsigned char)*p;
    char *end;unsigned expected=(unsigned)strtoul(f+1,&end,16);
    if(*end || expected!=checksum) return;
    *f=0;

    /* 字段 6：定位质量 */
    f = NmeaField(line, 6);
    if (f == NULL) return;
    if (*f >= '0' && *f <= '9') quality = (uint8_t)(*f - '0');
    else                        quality = 0;

    /* 字段 7：卫星数 */
    f = NmeaField(line, 7);
    sats = (f != NULL) ? (uint8_t)atoi(f) : 0;

    gps_info.fixQuality = quality;
    gps_info.sats       = sats;

    if (quality == 0) {
        gps_info.valid = 0;             /* 没定位：保留上次坐标，但不刷新时间戳 */
        return;
    }

    /* 字段 2/3：纬度 + 半球 */
    f = NmeaField(line, 2);
    if (f == NULL) return;
    lat_str = f;

    f = NmeaField(line, 3);
    if (f == NULL) return;
    hemi_lat = *f;

    /* 字段 4/5：经度 + 半球 */
    f = NmeaField(line, 4);
    if (f == NULL) return;
    lon_str = f;

    f = NmeaField(line, 5);
    if (f == NULL) return;
    hemi_lon = *f;
    if((*lat_str<'0'||*lat_str>'9') || (*lon_str<'0'||*lon_str>'9') ||
       (hemi_lat!='N'&&hemi_lat!='S') || (hemi_lon!='E'&&hemi_lon!='W')) {gps_info.valid=0;return;}

    double lat, lon;
    if (!NmeaToDegrees(lat_str,2,hemi_lat,&lat) || !NmeaToDegrees(lon_str,3,hemi_lon,&lon)) {
        gps_info.valid=0;
        return;
    }
    gps_info.latitude      = lat;
    gps_info.longitude     = lon;
    gps_info.valid         = 1;
    gps_info.last_fix_tick = HAL_GetTick();
}

/* ====================== 公开接口 ====================== */

void GPS_Init(void)
{
    memset((void *)&gps_info, 0, sizeof(gps_info));
    memset((void *)&gps_snapshot, 0, sizeof(gps_snapshot));
    memset(line_buf, 0, sizeof(line_buf));
    memset(last_line, 0, sizeof(last_line));

    rx_head  = 0;
    rx_tail  = 0;
    line_len = 0;

    HAL_UART_Receive_IT(&huart2, (uint8_t *)&rx_byte, 1);
}

void GPS_RxCpltCallback(void)
{
    RingPush(rx_byte);
}

uint8_t *GPS_GetRxBytePtr(void)
{
    return (uint8_t *)&rx_byte;
}

void GPS_Task(void)
{
    uint8_t b;

    while (RingPop(&b)) {
        if (b == '\n' || b == '\r') {
            if (line_len > 0) {
                line_buf[line_len] = '\0';

                /* 只解析 GGA（兼容 $GPGGA 单模 和 $GNGGA 多模） */
                if (line_len>=7 && line_buf[0]=='$' && !strncmp(line_buf+3,"GGA,",4)) {
                    ParseGGA(line_buf);
                    strncpy(last_line, line_buf, sizeof(last_line) - 1);
                    last_line[sizeof(last_line) - 1] = '\0';
                }
                line_len = 0;
            }
        } else {
            if (line_len < (GPS_LINE_SIZE - 1)) {
                line_buf[line_len++] = (char)b;
            } else {
                line_len = 0;              /* 超长（乱码）丢弃 */
            }
        }
    }

    /* 发布快照 */
    gps_snapshot = gps_info;
}

void GPS_GetInfo(GPS_Info *out)
{
    *out = gps_snapshot;
}

uint8_t GPS_HasFix(void)
{
    if (!gps_snapshot.valid) return 0;
    if ((HAL_GetTick() - gps_snapshot.last_fix_tick) > GPS_FIX_TIMEOUT_MS) {
        return 0;                          /* 定位数据太旧（天线被拔/失锁） */
    }
    return 1;
}

uint8_t GPS_GetDebugLine(char *buf, uint16_t maxLen)
{
    if (last_line[0] == '\0' || maxLen == 0) return 0;
    strncpy(buf, last_line, (size_t)(maxLen - 1));
    buf[maxLen - 1] = '\0';
    return 1;
}
