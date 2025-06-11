import 'package:flutter/material.dart';

class DataLogin extends ChangeNotifier {
  String uiduser;

  DataLogin({
    this.uiduser = "2LYCf5QJ2Mg4ONMpz9uMRVmKSz12",
  });
  void setuserlogin(String idne){
    this.uiduser = idne;
    notifyListeners();
  }
}