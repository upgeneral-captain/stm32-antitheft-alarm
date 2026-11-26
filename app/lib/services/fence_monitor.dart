import '../models/fence.dart';
import '../models/location_point.dart';
import 'geo_utils.dart';

class FenceMonitor {
  bool _outside=false;
  void reset() {_outside=false;}
  bool update(LocationPoint point,Fence fence,{required bool armed,required bool online,required bool valid}) {
    if(!armed || !online || !valid || !fence.active) {reset();return false;}
    final d=GeoUtils.distanceMeters(point.lat,point.lng,fence.lat,fence.lng);
    if(d<fence.radius-20) _outside=false;
    if(d>fence.radius+20 && !_outside) {_outside=true;return true;}
    return false;
  }
}
