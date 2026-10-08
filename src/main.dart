import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

const channel = MethodChannel('mouse');
void main() => runApp(const MaterialApp(debugShowCheckedModeBanner:false,home:MouseApp()));
class MouseApp extends StatefulWidget { const MouseApp({super.key}); @override State<MouseApp> createState()=>_MouseAppState(); }
class _MouseAppState extends State<MouseApp> {
  bool connected=false; double sensitivity=1.8, dxAcc=0,dyAcc=0,wheelAcc=0; int buttons=0;
  @override void initState(){super.initState(); channel.setMethodCallHandler((call) async {if(call.method=='state'&&mounted)setState(()=>connected=call.arguments as bool);}); _start();}
  Future<void> _start() async { await [Permission.bluetoothConnect,Permission.bluetoothScan,Permission.bluetoothAdvertise].request(); await channel.invokeMethod('start'); }
  void send(int x,int y,int wheel)=>channel.invokeMethod('send',[buttons,x,y,wheel]);
  void move(Offset d){dxAcc+=d.dx*sensitivity;dyAcc+=d.dy*sensitivity;final x=dxAcc.truncate(),y=dyAcc.truncate();dxAcc-=x;dyAcc-=y;if(x!=0||y!=0)send(x.clamp(-127,127),y.clamp(-127,127),0);}
  void button(int bit,bool down){setState(()=>buttons=down?buttons|bit:buttons&~bit);send(0,0,0);}
  Future<void> click() async {button(1,true);await Future.delayed(const Duration(milliseconds:50));button(1,false);}
  void scroll(double y){wheelAcc+=y;while(wheelAcc.abs()>=10){final s=wheelAcc>0?-1:1;send(0,0,s);wheelAcc+=wheelAcc>0?-10:10;}}
  Future<void> choose() async {final devices=await channel.invokeMethod<List>('devices')??[];if(!mounted)return;showModalBottomSheet(context:context,builder:(ctx)=>ListView(shrinkWrap:true,children:[const ListTile(title:Text('Kompyuterni tanlang (avval Bluetooth orqali juftlang)')),if(devices.isEmpty)const ListTile(title:Text('Juftlangan qurilma topilmadi')),for(final d in devices)ListTile(leading:const Icon(Icons.computer),title:Text(d['name']),onTap:(){Navigator.pop(ctx);channel.invokeMethod('connect',d['addr']);})]));}
  @override Widget build(BuildContext context)=>Scaffold(backgroundColor:const Color(0xff10101d),body:SafeArea(child:Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:Row(children:[Icon(Icons.circle,size:12,color:connected?Colors.green:Colors.red),const SizedBox(width:8),Text(connected?'Ulangan':'Ulanmagan',style:const TextStyle(color:Colors.white)),const Spacer(),IconButton(onPressed:choose,icon:const Icon(Icons.bluetooth,color:Colors.cyan))])),
    Row(children:[const Padding(padding:EdgeInsets.only(left:12),child:Icon(Icons.speed,color:Colors.white)),Expanded(child:Slider(value:sensitivity,min:.6,max:4,onChanged:(v)=>setState(()=>sensitivity=v)))]),
    Expanded(child:Column(children:[
      Expanded(flex:4,child:Row(children:[_mouseButton('CHAP',1),Expanded(flex:2,child:GestureDetector(onVerticalDragUpdate:(d)=>scroll(d.delta.dy),onTap:()=>button(4,true),child:Container(margin:const EdgeInsets.all(8),decoration:BoxDecoration(color:Colors.cyan,borderRadius:BorderRadius.circular(24)),child:const Center(child:Icon(Icons.more_vert))))),_mouseButton('O‘NG',2)])),
      Expanded(flex:6,child:GestureDetector(onPanUpdate:(d)=>move(d.delta),onTap:click,child:Container(margin:const EdgeInsets.all(12),decoration:BoxDecoration(color:const Color(0xff22223b),borderRadius:BorderRadius.circular(36),border:Border.all(color:Colors.cyan)),child:const Center(child:Text('TOUCHPAD',style:TextStyle(color:Colors.white54,letterSpacing:4))))))
    ]))
  ])));
  Widget _mouseButton(String text,int bit)=>Expanded(child:Listener(onPointerDown:(_)=>button(bit,true),onPointerUp:(_)=>button(bit,false),onPointerCancel:(_)=>button(bit,false),child:Container(margin:const EdgeInsets.all(8),decoration:BoxDecoration(color:const Color(0xff252542),borderRadius:BorderRadius.circular(20)),child:Center(child:Text(text,style:const TextStyle(color:Colors.white))))));
}