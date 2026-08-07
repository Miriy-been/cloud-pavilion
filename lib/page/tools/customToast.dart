import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 提示类型：成功（浅绿）/ 警告（浅黄）/ 失败（浅红）
enum ToastType { success, warning, error }

class CustomToast extends StatelessWidget {
  const CustomToast(this.msg,
      {Key? key, this.type = ToastType.warning})
      : super(key: key);

  final String msg;
  final ToastType type;

  @override
  Widget build(BuildContext context) {
    // 柔和底色 + 同色图标与文字，避免刺眼的纯色提示
    final (bg, fg, icon) = switch (type) {
      ToastType.success => (
          const Color(0xFFE7F6EC),
          const Color(0xFF1E8E4E),
          Icons.check_circle_rounded
        ),
      ToastType.error => (
          const Color(0xFFFDECEE),
          const Color(0xFFD63A3F),
          Icons.error_rounded
        ),
      ToastType.warning => (
          const Color(0xFFFFF3E0),
          const Color(0xFFE68A00),
          Icons.warning_amber_rounded
        ),
    };

    return Column(
      children: [
        SizedBox(height: 45),
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: EdgeInsets.only(bottom: 30),
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(100),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black12,
                      offset: Offset(0.0, 5.0), //阴影xy轴偏移量
                      blurRadius: 10.0, //阴影模糊程度
                      spreadRadius: 0.5 //阴影扩散程度
                      )
                ]),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              //icon
              Container(
                margin: EdgeInsets.only(right: 15),
                child: Icon(icon, color: fg),
              ),

              //msg
              Text('$msg',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: fg)),
            ]),
          ),
        )
      ],
    );
  }
}
