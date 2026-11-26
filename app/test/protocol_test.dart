import 'package:flutter_test/flutter_test.dart';
import 'package:alarm_app/services/mqtt_service.dart';
import 'package:alarm_app/services/fence_monitor.dart';
import 'package:alarm_app/models/fence.dart';
import 'package:alarm_app/models/location_point.dart';
import 'package:alarm_app/models/alarm_event.dart';
import 'package:alarm_app/services/geo_utils.dart';

void main() {
  test('GPS-less alarm is delivered and state is updated',() {
    final m=MqttService.instance;var alarms=0;bool? armed;
    m.onAlarm=(_) => alarms++;m.onState=(s)=>armed=s.armed;
    m.receiveForTest('state001','{"armed":1,"alarm":1,"batt":null,"state":"alarm"}');
    expect(alarms,1);expect(armed,true);expect(m.devicePhase,'alarm');
  });
  test('alarm does not suppress location and rejects foreign topics',() {
    final m=MqttService.instance;var locations=0,alarms=0;
    m.onAlarm=(_)=>alarms++;m.onLocation=(_)=>locations++;
    m.receiveForTest('state001','{"armed":1,"alarm":1,"lat":30.6,"lng":104.0}');
    expect(locations,1);expect(alarms,1);
    m.receiveForTest('other','{"alarm":1}');expect(alarms,1);
  });
  test('lost fix and invalid positions are rejected',() {
    expect(LocationPoint.tryParse({'lat':30,'lng':104,'fix':0}),null);
    expect(LocationPoint.tryParse({'lat':double.nan,'lng':104}),null);
    expect(LocationPoint.tryParse({'lat':30,'lng':104,'ageMs':6000}),null);
  });
  test('fence only fires once outside while armed and rearms inside',() {
    final m=FenceMonitor();const f=Fence(enabled:true,lat:30,lng:104,radius:100);
    const out=LocationPoint(lat:30.01,lng:104,time:'',receivedAt:0);
    const inside=LocationPoint(lat:30,lng:104,time:'',receivedAt:0);
    expect(m.update(out,f,armed:false,online:true,valid:true),false);
    expect(m.update(out,f,armed:true,online:true,valid:true),true);
    expect(m.update(out,f,armed:true,online:true,valid:true),false);
    expect(m.update(inside,f,armed:true,online:true,valid:true),false);
    expect(m.update(out,f,armed:true,online:true,valid:true),true);
  });
  test('unknown position cannot be presented as known coordinates',() {
    final e=AlarmEvent.create(type:AlarmType.device,lat:0,lng:0);
    expect(e.hasLocation,false);expect(e.coordText,'当前位置未知');
  });
  test('WGS84 converts once and coordinates outside China stay unchanged',() {
    final p=GeoUtils.wgsToGcj(39.9,116.3);
    expect((p.$2-116.3).abs(),greaterThan(0.001));
    expect(GeoUtils.wgsToGcj(51.5,-0.1),(51.5,-0.1));
    final g=LocationPoint.tryParse({'lat':p.$1,'lng':p.$2,'coord':'gcj02'})!;
    expect(g.lat,p.$1);expect(g.lng,p.$2);
  });
  test('offline command cannot optimistically arm the device',() async {
    expect(await MqttService.instance.sendArm(true),false);
  });
}
