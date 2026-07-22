import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'arcade_center_screen.dart' show AppLanguage;
import 'arcade_input_controller.dart';
import 'game_saldo.dart';
import 'high_score_service.dart';

const _kMapW = 32, _kMapH = 32;

const _kMap = <List<int>>[
  [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,1,0,1],
  [1,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,1,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1],
  [1,0,0,1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,1,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
];

const _kLavaTowers0 = <List<int>>[
  [12,12],[19,12],[12,19],[19,19],
  [15,15],[16,16],
];

const _kMap1 = <List<int>>[
  [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
];

const _kLavaTowers1 = <List<int>>[
  [12,12],[20,12],[16,16],[12,20],[20,20],
  [8,8],[24,8],[8,24],[24,24],
];

const _kMap2 = <List<int>>[
  [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0,0,1],
  [1,0,0,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0,0,1],
  [1,0,0,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,1,1,1,1,0,0,1,1,1,1,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,1,1,1,1,0,0,1,1,1,1,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0,0,1],
  [1,0,0,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0,0,1],
  [1,0,0,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
];

const _kLavaTowers2 = <List<int>>[
  [11,11],[20,11],[11,20],[20,20],
  [5,5],[26,5],[5,26],[26,26],
];

const _kMap3 = <List<int>>[
  [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,1,0,0,0,0,1,1,0,0,1,1,0,0,0,0,1,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,1,0,0,0,0,1,1,0,0,1,1,0,0,0,0,1,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
];

const _kLavaTowers3 = <List<int>>[
  [13,13],[18,13],[13,18],[18,18],
  [8,8],[23,8],[8,23],[23,23],
];

const _kMaps = [_kMap, _kMap1, _kMap2, _kMap3];

const _kRealmLavaTowers = [_kLavaTowers0, _kLavaTowers1, _kLavaTowers2, _kLavaTowers3];

const _kRealmNames  = ['La Cripta',             'Las Catacumbas',         'El Abismo',              'El Núcleo del Infierno'];
const _kRealmNamesEn = ['The Crypt',            'The Catacombs',          'The Abyss',              'The Hell Core'];
const _kRealmTaglines   = ['Las sombras te acechan…', '¡Los muertos caminan!', 'El vacío te llama…',  '¡No hay escapatoria!'];
const _kRealmTaglinesEn = ['Shadows stalk you…',     'The dead walk!',        'The void calls you…', 'There is no escape!'];
const _kRealmSpawn = [[2.5, 2.5], [2.5, 2.5], [2.5, 2.5], [2.5, 2.5]];

enum _EnemyType { demon, cacodemon, skeleton, troll }

class _Enemy {
  double x, y;
  double hp;
  bool alive;
  double hitFlash;
  _EnemyType type;
  int wave;
  bool isMega;

  _Enemy(this.x, this.y, {this.type = _EnemyType.demon, this.wave = 1, this.isMega = false})
      : hp = _baseHp(type) * (1.0 + (wave - 1) * 0.25) * (isMega ? 3.0 : 1.0),
        alive = true,
        hitFlash = 0;

  double crosshairTimer = 0.0;
  double teleportFlash = 0.0;

  double flinchVx = 0.0;
  double flinchVy = 0.0;
  double flinchTimer = 0.0;

  double dodgeDir = 1.0;
  double dodgeTimer = 0.0;
  static const double kDodgeDuration = 0.45;

  double steerBias = 1.0;
  double stuckTimer = 0.0;

  List<List<int>> navPath = [];
  double pathTimer = 0.0;
  static const double kPathInterval = 1.2;

  static double _baseHp(_EnemyType t) {
    switch (t) {
      case _EnemyType.demon:     return 3;
      case _EnemyType.cacodemon: return 2;
      case _EnemyType.skeleton:  return 1;
      case _EnemyType.troll:     return 10;
    }
  }

  double get spriteScale {
    if (isMega) return 0.96;
    switch (type) {
      case _EnemyType.demon:     return 0.783;
      case _EnemyType.cacodemon: return 0.81;
      case _EnemyType.skeleton:  return 0.81;
      case _EnemyType.troll:     return 0.702;
    }
  }

  double get speed {
    switch (type) {
      case _EnemyType.skeleton:  return 0.90;
      case _EnemyType.cacodemon: return 1.50;
      case _EnemyType.troll:     return 1.90;
      default:                   return 1.30;
    }
  }

  double get _baseDamage {
    switch (type) {
      case _EnemyType.skeleton:  return 15.0;
      case _EnemyType.cacodemon: return 7.0;
      case _EnemyType.troll:     return 22.0;
      default:                   return 10.0;
    }
  }

  double get damage => (_baseDamage * (1.0 + (wave - 1) * 0.15)).clamp(0, _baseDamage * 3);

  double get attackRange {
    switch (type) {
      case _EnemyType.skeleton:  return 7.0;
      case _EnemyType.cacodemon: return 5.5;
      case _EnemyType.troll:     return 5.5;
      default:                   return 0.0;
    }
  }
  double get attackInterval {
    switch (type) {
      case _EnemyType.skeleton:  return 1.8;
      case _EnemyType.cacodemon: return 2.4;
      case _EnemyType.troll:     return 2.0;
      default:                   return 0.0;
    }
  }
  double get projectileDmg {
    switch (type) {
      case _EnemyType.skeleton:  return (10.0 * (1.0 + (wave-1) * 0.15)).clamp(0, 30.0);
      case _EnemyType.cacodemon: return (6.0  * (1.0 + (wave-1) * 0.15)).clamp(0, 18.0);
      case _EnemyType.troll:     return (18.0 * (1.0 + (wave-1) * 0.15)).clamp(0, 54.0);
      default:                   return 0.0;
    }
  }
  double get projectileSpeed {
    switch (type) {
      case _EnemyType.skeleton:  return 5.0;
      case _EnemyType.cacodemon: return 3.5;
      case _EnemyType.troll:     return 4.5;
      default:                   return 0.0;
    }
  }
  double get minEngageRange  => (attackRange > 0 && type != _EnemyType.troll) ? 2.0 : 0.0;

  double attackCooldown = 0;
}

class _Projectile {
  double x, y;
  double dx, dy;
  double speed;
  double damage;
  _EnemyType type;
  bool alive = true;
  double dist = 0;

  static const double maxRange = 22.0;

  _Projectile({required this.x, required this.y,
      required this.dx, required this.dy,
      required this.speed, required this.damage,
      required this.type});
}

class _ANode {
  final int c, r, g, h;
  final _ANode? parent;
  int get f => g + h;
  const _ANode(this.c, this.r, this.g, this.h, this.parent);
}

enum _WeaponType { pistol, shotgun, smg }

enum _GameState { start, playing, dead }

class RaycasterScreen extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;
  final ArcadeInputController controller;
  final void Function(double) onSaldoChanged;
  final AppLanguage language;

  const RaycasterScreen({
    super.key,
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
    required this.controller,
    required this.onSaldoChanged,
    this.language = AppLanguage.spanish,
  });

  @override
  State<RaycasterScreen> createState() => _RaycasterScreenState();
}

class _RaycasterScreenState extends State<RaycasterScreen> {
  double _posX = 2.5, _posY = 2.5;
  double _dirX = 1.0, _dirY = 0.0;
  double _planeX = 0.0, _planeY = 0.66;
  double _health = 100.0;
  int _kills = 0;
  int _wave = 1;
  int _ammo = 30;
  int _shotgunAmmo = 0;
  bool _shotgunUnlocked = false;
  int _smgAmmo = 0;
  bool _smgUnlocked = false;
  _WeaponType _weapon = _WeaponType.pistol;
  double _fireTimer = 0;
  double _time = 0;
  double _damageCooldown = 0;

  late double _saldo;
  late double _lastCommitted;
  int _hiScore = 0;

  _GameState _state = _GameState.start;
  bool _paused = false;
  Timer? _gameTimer;
  DateTime? _lastTick;

  double _hitFlash = 0;
  double _shootFlash = 0;
  double _waveBannerTimer = 0;
  double _dimFlash = 0;
  double _dimTimer = 0;

  String _waveFlavorText = '';
  bool _relicActive = false;
  double _relicX = 7.5, _relicY = 7.5;

  int _currentRealm = 0;
  double _realmTransitionTimer = 0;

  List<List<int>> get _currentMap => _kMaps[_currentRealm.clamp(0, _kMaps.length - 1)];

  bool get _megaAlive => _enemies.any((e) => e.alive && e.isMega);

  final List<_Enemy> _enemies = [];
  final List<_Projectile> _projectiles = [];
  final List<double> _zBuf = List<double>.filled(240, 0);
  final Random _rng = Random();

  static const double _moveSpeed = 3.2;
  static const double _rotSpeed = 2.5;

  static const _kModSequence = [
    ArcadeButton.up, ArcadeButton.up,
    ArcadeButton.down, ArcadeButton.down,
    ArcadeButton.left, ArcadeButton.right,
    ArcadeButton.left, ArcadeButton.b,
  ];
  int _modSeqIdx = 0;
  bool _modMenuOpen = false;
  int _modCursor = 0;
  // Dev tool: the mod menu makes the payout unlimited, so only the admin
  // allow-list can reach it. Resolved once — the uid can't change mid-game.
  bool _isAdmin = false;

  bool _modUnlimitedAmmo = false;
  bool _modAimbot       = false;
  bool _modGodMode      = false;
  bool _modInstantKill  = false;

  String _t(String es, String en) =>
      widget.language == AppLanguage.spanish ? es : en;

  @override
  void initState() {
    super.initState();
    _saldo = widget.currentSaldo;
    _lastCommitted = widget.currentSaldo;
    _isAdmin = isArcadeAdmin();
    widget.controller.addListener(_onControllerEvent);
    HighScoreService.load('raycaster').then((v) => setState(() => _hiScore = v));
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    widget.controller.removeListener(_onControllerEvent);
    super.dispose();
  }

  void _onControllerEvent() {
    final event = widget.controller.lastEvent;
    if (event == null) return;

    if (_state == _GameState.start) {
      if (event.isDown && (event.button == ArcadeButton.start || event.button == ArcadeButton.a)) {
        _startGame();
      }
      return;
    }
    if (_state == _GameState.dead) {
      if (event.isDown && (event.button == ArcadeButton.start || event.button == ArcadeButton.a)) {
        _restart();
      }
      return;
    }
    // Non-admins: sequence isn't even tracked, so the menu can't be opened.
    if (_isAdmin && event.isDown && _state == _GameState.playing) {
      if (event.button == _kModSequence[_modSeqIdx]) {
        _modSeqIdx++;
        if (_modSeqIdx >= _kModSequence.length) {
          _modSeqIdx = 0;
          setState(() => _modMenuOpen = !_modMenuOpen);
          HapticFeedback.heavyImpact();
          return;
        }
      } else {
        _modSeqIdx = (event.button == _kModSequence[0]) ? 1 : 0;
      }
    }

    if (_modMenuOpen && event.isDown) {
      switch (event.button) {
        case ArcadeButton.up:
          setState(() => _modCursor = (_modCursor - 1).clamp(0, 3));
          return;
        case ArcadeButton.down:
          setState(() => _modCursor = (_modCursor + 1).clamp(0, 3));
          return;
        case ArcadeButton.a:
          setState(() {
            switch (_modCursor) {
              case 0: _modUnlimitedAmmo = !_modUnlimitedAmmo;
              case 1: _modAimbot       = !_modAimbot;
              case 2: _modGodMode      = !_modGodMode;
              case 3: _modInstantKill  = !_modInstantKill;
            }
          });
          HapticFeedback.selectionClick();
          return;
        case ArcadeButton.b:
        case ArcadeButton.start:
          setState(() => _modMenuOpen = false);
          return;
        default:
          break;
      }
    }
    if (_modMenuOpen) return;

    if (event.isDown && event.button == ArcadeButton.start) {
      setState(() => _paused = !_paused);
      return;
    }
    if (_paused) return;
    if (event.isDown && event.button == ArcadeButton.a) {
      _fire();
    }
    if (event.isDown && event.button == ArcadeButton.b) {
      setState(() {
        final options = [
          _WeaponType.pistol,
          if (_shotgunUnlocked) _WeaponType.shotgun,
          if (_smgUnlocked) _WeaponType.smg,
        ];
        final idx = options.indexOf(_weapon);
        _weapon = options[(idx + 1) % options.length];
      });
      HapticFeedback.selectionClick();
    }
  }

  void _startGame() {
    setState(() {
      _posX = 2.5; _posY = 2.5;
      _dirX = 1.0; _dirY = 0.0;
      _planeX = 0.0; _planeY = 0.66;
      _health = 100.0;
      _kills = 0;
      _wave = 1;
      _ammo = 30;
      _shotgunAmmo = 0;
      _shotgunUnlocked = false;
      _smgAmmo = 0;
      _smgUnlocked = false;
      _weapon = _WeaponType.pistol;
      _fireTimer = 0;
      _time = 0;
      _damageCooldown = 0;
      _hitFlash = 0;
      _shootFlash = 0;
      _waveBannerTimer = 0;
      _dimFlash = 0;
      _dimTimer = 4.0 + _rng.nextDouble() * 6.0;
      _waveFlavorText = '';
      _relicActive = false;
      _currentRealm = 0;
      _realmTransitionTimer = 0;
      _state = _GameState.playing;
    });
    _spawnWave(1);
    _lastTick = DateTime.now();
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(milliseconds: 16), _tick);
  }

  Future<void> _restart() async {
    final ns = await chargeForReplay(
        userId: widget.userId,
        rewardsDocRef: widget.rewardsDocRef,
        currentSaldo: _saldo);
    if (ns == null) return;
    if (!mounted) return;
    // Resync the ledger: the replay charge already moved the server saldo, so
    // without this _lastCommitted stays one play-cost above _saldo and the
    // next credit computes a negative delta — debiting the player.
    _lastCommitted = ns;
    setState(() => _saldo = ns);
    widget.onSaldoChanged(ns);
    _startGame();
  }

  _EnemyType _randomType(int wave) {
    if (wave == 1) return _EnemyType.demon;
    if (wave == 2) return _rng.nextBool() ? _EnemyType.demon : _EnemyType.cacodemon;
    if (wave >= 5) {
      final trollChance = ((wave - 4) * 0.08).clamp(0.0, 0.30);
      if (_rng.nextDouble() < trollChance) return _EnemyType.troll;
    }
    final r = _rng.nextInt(3);
    return _EnemyType.values[r];
  }

  void _spawnWave(int wave) {
    _enemies.clear();
    _projectiles.clear();
    if (wave == 1) {
      _enemies.addAll([
        _Enemy(15.5, 8.5,  type: _EnemyType.demon,     wave: wave),
        _Enemy(15.5, 22.5, type: _EnemyType.cacodemon,  wave: wave),
        _Enemy(14.5, 15.5, type: _EnemyType.demon,      wave: wave),
        _Enemy(24.5, 8.5,  type: _EnemyType.skeleton,   wave: wave),
      ]);
      return;
    }

    if (wave % 5 == 0) {
      _enemies.add(_Enemy(14.5, 14.5, type: _EnemyType.demon, wave: wave * 2, isMega: true));
    }

    final map = _currentMap;
    final count = wave + 3;
    int spawned = 0, tries = 0;
    while (spawned < count && tries < 500) {
      tries++;
      final cx = 1 + _rng.nextInt(_kMapW - 2);
      final cy = 1 + _rng.nextInt(_kMapH - 2);
      if (map[cy][cx] == 1) continue;
      final ex = cx + 0.5, ey = cy + 0.5;
      final dx = ex - _posX, dy = ey - _posY;
      if (dx * dx + dy * dy < 9) continue;
      final enemy = _Enemy(ex, ey, type: _randomType(wave), wave: wave);
      _enemies.add(enemy);
      spawned++;
    }
  }

  void _fire() {
    if (_weapon == _WeaponType.shotgun) {
      _fireShotgun();
    } else if (_weapon == _WeaponType.smg) {
      _fireSmg();
    } else {
      _firePistol();
    }
  }

  void _firePistol() {
    if (_fireTimer > 0) return;
    if (_ammo <= 0) { HapticFeedback.lightImpact(); return; }
    if (!_modUnlimitedAmmo) _ammo--;
    _fireTimer = 0.25;
    _shootFlash = 1.0;
    HapticFeedback.lightImpact();
    _checkCenterHit(_dirX, _dirY, 22.0, damage: 1);
  }

  void _fireShotgun() {
    if (_fireTimer > 0) return;
    if (_shotgunAmmo <= 0) { HapticFeedback.lightImpact(); return; }
    if (!_modUnlimitedAmmo) _shotgunAmmo--;
    _fireTimer = 0.55;
    _shootFlash = 1.0;
    HapticFeedback.heavyImpact();

    const pellets = 7;
    const spread = 0.38;
    for (int p = 0; p < pellets; p++) {
      final angle = -spread + (p / (pellets - 1)) * 2 * spread;
      final cosA = cos(angle), sinA = sin(angle);
      final rDx = _dirX * cosA - _dirY * sinA;
      final rDy = _dirX * sinA + _dirY * cosA;
      _checkCenterHit(rDx, rDy, 12.0, damage: 1);
    }
  }

  void _fireSmg() {
    if (_fireTimer > 0) return;
    if (_smgAmmo <= 0) { HapticFeedback.lightImpact(); return; }
    if (!_modUnlimitedAmmo) _smgAmmo--;
    _fireTimer = 0.08;
    _shootFlash = 0.6;
    HapticFeedback.lightImpact();
    final spread = (_rng.nextDouble() - 0.5) * 0.12;
    final cosA = cos(spread), sinA = sin(spread);
    final rDx = _dirX * cosA - _dirY * sinA;
    final rDy = _dirX * sinA + _dirY * cosA;
    _checkCenterHit(rDx, rDy, 18.0, damage: 1);
  }

  List<List<int>>? _astar(int sc, int sr, int gc, int gr, List<List<int>> map) {
    if (sc == gc && sr == gr) return [];
    const dirs = [[0,-1],[0,1],[-1,0],[1,0]];
    final open = <_ANode>[];
    final closed = <int, _ANode>{};
    final start = _ANode(sc, sr, 0, (gc-sc).abs() + (gr-sr).abs(), null);
    open.add(start);
    while (open.isNotEmpty) {
      open.sort((a, b) => a.f.compareTo(b.f));
      final cur = open.removeAt(0);
      final key = cur.c * 64 + cur.r;
      if (closed.containsKey(key)) continue;
      closed[key] = cur;
      if (cur.c == gc && cur.r == gr) {
        final path = <List<int>>[];
        _ANode? n = cur;
        while (n != null && !(n.c == sc && n.r == sr)) {
          path.add([n.c, n.r]);
          n = n.parent;
        }
        return path.reversed.toList();
      }
      if (closed.length > 512) break;
      for (final d in dirs) {
        final nc = cur.c + d[0], nr = cur.r + d[1];
        if (nc < 1 || nc >= _kMapW - 1 || nr < 1 || nr >= _kMapH - 1) continue;
        if (map[nr][nc] == 1) continue;
        final nk = nc * 64 + nr;
        if (closed.containsKey(nk)) continue;
        final g = cur.g + 1;
        final h = (gc - nc).abs() + (gr - nr).abs();
        open.add(_ANode(nc, nr, g, h, cur));
      }
    }
    return null;
  }

  bool _hasLos(double x0, double y0, double x1, double y1) {
    final dx = x1 - x0, dy = y1 - y0;
    final steps = (dx.abs() + dy.abs()) * 4;
    if (steps < 1) return true;
    final map = _currentMap;
    for (int i = 1; i < steps; i++) {
      final t = i / steps;
      final mx = (x0 + dx * t).floor();
      final my = (y0 + dy * t).floor();
      if (mx < 0 || mx >= _kMapW || my < 0 || my >= _kMapH) return false;
      if (map[my][mx] == 1) return false;
    }
    return true;
  }

  void _checkCenterHit(double rayDirX, double rayDirY, double maxRange, {int damage = 1}) {
    double bestDist = maxRange;
    _Enemy? target;
    for (final e in _enemies) {
      if (!e.alive) continue;
      final dx = e.x - _posX, dy = e.y - _posY;
      final dot = dx * rayDirX + dy * rayDirY;
      if (dot <= 0 || dot > bestDist) continue;
      final perp = (dx * rayDirY - dy * rayDirX).abs();
      if (perp < 0.75 && _hasLos(_posX, _posY, e.x, e.y)) {
        bestDist = dot;
        target = e;
      }
    }
    if (target != null) {
      target.hp -= _modInstantKill ? 9999 : damage;
      target.hitFlash = 1.0;
      final fdx = target.x - _posX, fdy = target.y - _posY;
      final fd = sqrt(fdx * fdx + fdy * fdy);
      if (fd > 0.01) {
        target.flinchVx = fdx / fd * 2.2;
        target.flinchVy = fdy / fd * 2.2;
        target.flinchTimer = 0.18;
      }
      if (target.hp <= 0) {
        target.alive = false;
        _kills++;
        HapticFeedback.mediumImpact();
        _checkWaveComplete();
      }
    }
  }

  void _trollTeleport(_Enemy e, List<List<int>> map) {
    int tries = 0;
    while (tries++ < 200) {
      final tx = 1.5 + _rng.nextDouble() * (_kMapW - 3);
      final ty = 1.5 + _rng.nextDouble() * (_kMapH - 3);
      final mx = tx.floor(), my = ty.floor();
      if (mx < 0 || mx >= _kMapW || my < 0 || my >= _kMapH) continue;
      if (map[my][mx] != 0) continue;
      final ddx = tx - _posX, ddy = ty - _posY;
      final dSq = ddx * ddx + ddy * ddy;
      if (dSq < 4.0 || dSq > 72.0) continue;
      e.x = tx; e.y = ty;
      e.teleportFlash = 1.0;
      HapticFeedback.selectionClick();
      break;
    }
  }

  void _checkWaveComplete() {
    if (_enemies.any((e) => e.alive)) return;
    _wave++;
    _ammo += 30;
    _health = (_health + 15).clamp(0, 100.0);

    final newRealm = ((_wave - 1) ~/ 10).clamp(0, _kMaps.length - 1);
    if (newRealm > _currentRealm) {
      _currentRealm = newRealm;
      _realmTransitionTimer = 4.0;
      final spawn = _kRealmSpawn[_currentRealm];
      _posX = spawn[0]; _posY = spawn[1];
      _dirX = 1.0; _dirY = 0.0;
      _planeX = 0.0; _planeY = 0.66;
      _health = 100.0;
    }

    if (_wave == 2) {
      _shotgunUnlocked = true;
      _shotgunAmmo += 6;
    } else if (_wave > 2) {
      _shotgunAmmo += 6;
    }
    if (_wave == 4) {
      _smgUnlocked = true;
      _smgAmmo += 20;
    } else if (_wave > 4) {
      _smgAmmo += 20;
    }

    if (_wave % 3 == 0) {
      _relicActive = true;
      _relicX = 14.5; _relicY = 14.5;
    }

    final isBoss = _wave % 5 == 0;
    _waveFlavorText = _realmTransitionTimer > 0
        ? _t('⚡ ¡NUEVO REINO DESBLOQUEADO! ⚡', '⚡ NEW REALM UNLOCKED! ⚡')
        : _getFlavorText(_wave, isBoss);
    _waveBannerTimer = (isBoss || _realmTransitionTimer > 0) ? 4.0 : 2.5;

    _saldo += 1;
    widget.onSaldoChanged(_saldo);
    _updateFirestore(_saldo);
    HapticFeedback.heavyImpact();
    _spawnWave(_wave);
  }

  String _getFlavorText(int wave, bool isBoss) {
    if (isBoss) return _t('☠  ¡¡JEFE INVOCADO!!  ☠', '☠  BOSS SUMMONED!!  ☠');
    final texts = widget.language == AppLanguage.spanish
        ? const [
            'La oscuridad se intensifica…',
            '¡Más demonios despiertan!',
            '✨ Un relicario aparece ✨',
            'La cripta tiembla de furia…',
            '¡Resistid si podéis!',
            'El reino infernal avanza…',
            'Los muertos no descansan…',
            'Sangre y fuego te esperan…',
          ]
        : const [
            'The darkness intensifies…',
            'More demons awaken!',
            '✨ A relic appears ✨',
            'The crypt shakes with fury…',
            'Resist if you can!',
            'The infernal realm advances…',
            'The dead do not rest…',
            'Blood and fire await you…',
          ];
    return texts[(wave - 2) % texts.length];
  }

  void _tick(Timer t) {
    if (_state != _GameState.playing || _paused) return;
    final now = DateTime.now();
    final dt = _lastTick == null ? 0.016 : now.difference(_lastTick!).inMicroseconds / 1e6;
    _lastTick = now;
    final dts = dt.clamp(0.001, 0.1);
    _time += dts;
    _processMovement(dts);
    _updateEnemies(dts);
    _updateProjectiles(dts);
    _updateTimers(dts);
    _checkRelic();
    setState(() {});
  }

  void _processMovement(double dt) {
    final c = widget.controller;
    if (_modAimbot) {
      _Enemy? nearest;
      double bestAbsDiff = double.infinity;
      for (final e in _enemies) {
        if (!e.alive) continue;
        final dx = e.x - _posX, dy = e.y - _posY;
        final targetAngle = atan2(dy, dx);
        final curAngle = atan2(_dirY, _dirX);
        var diff = targetAngle - curAngle;
        while (diff > pi)  diff -= 2 * pi;
        while (diff < -pi) diff += 2 * pi;
        if (diff.abs() < 0.58 && diff.abs() < bestAbsDiff &&
            _hasLos(_posX, _posY, e.x, e.y)) {
          bestAbsDiff = diff.abs();
          nearest = e;
        }
      }
      if (nearest != null) {
        final dx = nearest.x - _posX, dy = nearest.y - _posY;
        final targetAngle = atan2(dy, dx);
        final curAngle = atan2(_dirY, _dirX);
        var diff = targetAngle - curAngle;
        while (diff > pi)  diff -= 2 * pi;
        while (diff < -pi) diff += 2 * pi;
        const kScreenThreshold = 0.074;
        if (diff.abs() < kScreenThreshold) {
          final step = (_rotSpeed * 0.35 * dt).clamp(0.0, diff.abs());
          if (diff.abs() > 0.002) _rotate(diff > 0 ? step : -step);
        }
      }
    }
    if (_weapon == _WeaponType.smg && c.isHeld(ArcadeButton.a)) {
      _fireSmg();
    }
    final map = _currentMap;
    if (c.isHeld(ArcadeButton.up)) {
      final nx = _posX + _dirX * _moveSpeed * dt;
      final ny = _posY + _dirY * _moveSpeed * dt;
      if (map[_posY.floor()][nx.floor()] == 0) _posX = nx;
      if (map[ny.floor()][_posX.floor()] == 0) _posY = ny;
    }
    if (c.isHeld(ArcadeButton.down)) {
      final nx = _posX - _dirX * _moveSpeed * dt;
      final ny = _posY - _dirY * _moveSpeed * dt;
      if (map[_posY.floor()][nx.floor()] == 0) _posX = nx;
      if (map[ny.floor()][_posX.floor()] == 0) _posY = ny;
    }
    if (c.isHeld(ArcadeButton.left)) _rotate(-_rotSpeed * dt);
    if (c.isHeld(ArcadeButton.right)) _rotate(_rotSpeed * dt);
  }

  void _rotate(double angle) {
    final cosA = cos(angle), sinA = sin(angle);
    final ndx = _dirX * cosA - _dirY * sinA;
    final ndy = _dirX * sinA + _dirY * cosA;
    _dirX = ndx; _dirY = ndy;
    final npx = _planeX * cosA - _planeY * sinA;
    final npy = _planeX * sinA + _planeY * cosA;
    _planeX = npx; _planeY = npy;
  }

  void _updateEnemies(double dt) {
    final eBaseSpeed = 1.4 + _wave * 0.18;
    final map = _currentMap;
    for (final e in _enemies) {
      if (!e.alive) continue;

      if (e.type == _EnemyType.troll) {
        if (e.teleportFlash > 0) e.teleportFlash = (e.teleportFlash - dt * 3.0).clamp(0, 1);

        final toTrollX = e.x - _posX, toTrollY = e.y - _posY;
        final trollDist = sqrt(toTrollX * toTrollX + toTrollY * toTrollY);
        if (trollDist > 0.1) {
          final dot  = toTrollX * _dirX + toTrollY * _dirY;
          final perp = (toTrollX * _dirY - toTrollY * _dirX).abs();
          final inCrosshairs = dot > 0 && (perp / trollDist) < 0.25
              && _hasLos(_posX, _posY, e.x, e.y);
          if (inCrosshairs) {
            e.crosshairTimer += dt;
            if (e.crosshairTimer >= 0.4) {
              e.crosshairTimer = 0.0;
              _trollTeleport(e, map);
            }
          } else {
            e.crosshairTimer = (e.crosshairTimer - dt * 1.0).clamp(0.0, 0.4);
          }
        }
      }

      final dx = _posX - e.x, dy = _posY - e.y;
      final dist = sqrt(dx * dx + dy * dy);

      if (e.type == _EnemyType.troll) {
        if (dist < 0.8) {
          if (!_modGodMode) _health -= e.damage * dt;
          _hitFlash = (_hitFlash + dt * 3).clamp(0, 1);
          if (_damageCooldown <= 0) {
            HapticFeedback.lightImpact();
            _damageCooldown = 0.35;
          }
          if (_health <= 0) { _health = 0; _gameOver(); return; }
        } else if (e.attackCooldown <= 0 && dist < e.attackRange &&
            _hasLos(e.x, e.y, _posX, _posY)) {
          _projectiles.add(_Projectile(
            x: e.x, y: e.y,
            dx: dx / dist, dy: dy / dist,
            speed: e.projectileSpeed,
            damage: e.projectileDmg,
            type: e.type,
          ));
          e.attackCooldown = e.attackInterval;
        }
      } else if (e.attackRange == 0) {
        if (dist < 0.5) {
          if (!_modGodMode) _health -= e.damage * dt;
          _hitFlash = (_hitFlash + dt * 3).clamp(0, 1);
          if (_damageCooldown <= 0) {
            HapticFeedback.lightImpact();
            _damageCooldown = 0.35;
          }
          if (_health <= 0) { _health = 0; _gameOver(); return; }
          continue;
        }
      } else {
        if (e.attackCooldown <= 0 &&
            dist > 0.5 && dist < e.attackRange &&
            _hasLos(e.x, e.y, _posX, _posY)) {
          _projectiles.add(_Projectile(
            x: e.x, y: e.y,
            dx: dx / dist, dy: dy / dist,
            speed: e.projectileSpeed,
            damage: e.projectileDmg,
            type: e.type,
          ));
          e.attackCooldown = e.attackInterval;
        }
        if (dist <= e.minEngageRange) continue;
      }

      const kER = 0.32;
      final spd = eBaseSpeed * e.speed;
      if (dist < 0.01) continue;

      e.pathTimer += dt;
      final hasDirectLos = _hasLos(e.x, e.y, _posX, _posY);
      final needsRepath = e.pathTimer >= _Enemy.kPathInterval
          || (e.navPath.isEmpty && !hasDirectLos);
      if (needsRepath) {
        e.pathTimer = 0.0;
        if (hasDirectLos) {
          e.navPath = [];
        } else {
          final path = _astar(
            e.x.floor(), e.y.floor(),
            _posX.floor(), _posY.floor(),
            map,
          );
          e.navPath = path ?? [];
        }
      }

      double ndx, ndy;
      if (e.navPath.isNotEmpty) {
        final waypoint = e.navPath.first;
        final wpX = waypoint[0] + 0.5, wpY = waypoint[1] + 0.5;
        final wdx = wpX - e.x, wdy = wpY - e.y;
        final wdist = sqrt(wdx * wdx + wdy * wdy);
        if (wdist < 0.35) {
          e.navPath = e.navPath.sublist(1);
          if (e.navPath.isEmpty) { ndx = dx / dist; ndy = dy / dist; }
          else {
            final nw = e.navPath.first;
            final nwx = nw[0] + 0.5 - e.x, nwy = nw[1] + 0.5 - e.y;
            final nd = sqrt(nwx*nwx + nwy*nwy);
            ndx = nd > 0.01 ? nwx/nd : dx/dist;
            ndy = nd > 0.01 ? nwy/nd : dy/dist;
          }
        } else {
          ndx = wdx / wdist; ndy = wdy / wdist;
        }
      } else {
        ndx = dx / dist; ndy = dy / dist;
      }

      if (e.dodgeTimer <= 0) {
        for (final p in _projectiles) {
          if (!p.alive) continue;
          final pdx = e.x - p.x, pdy = e.y - p.y;
          final dot = pdx * p.dx + pdy * p.dy;
          if (dot > 0 && dot < 2.8) {
            final perp = (pdx * p.dy - pdy * p.dx).abs();
            if (perp < 0.9) {
              e.dodgeDir = _rng.nextBool() ? 1.0 : -1.0;
              e.dodgeTimer = _Enemy.kDodgeDuration;
              break;
            }
          }
        }
      }
      double moveX = ndx, moveY = ndy;
      if (e.dodgeTimer > 0) {
        e.dodgeTimer -= dt;
        final t = (e.dodgeTimer / _Enemy.kDodgeDuration).clamp(0.0, 1.0);
        final perpX = -ndy * e.dodgeDir;
        final perpY =  ndx * e.dodgeDir;
        final blend = 0.55 + t * 0.30;
        moveX = ndx * (1.0 - blend) + perpX * blend;
        moveY = ndy * (1.0 - blend) + perpY * blend;
        final mlen = sqrt(moveX * moveX + moveY * moveY);
        if (mlen > 0.01) { moveX /= mlen; moveY /= mlen; }
      }

      if (e.flinchTimer > 0) {
        e.flinchTimer -= dt;
        final fnx = e.x + e.flinchVx * dt;
        final fny = e.y + e.flinchVy * dt;
        if (map[e.y.floor()][(fnx - kER).floor()] == 0 &&
            map[e.y.floor()][(fnx + kER).floor()] == 0) e.x = fnx;
        if (map[(fny - kER).floor()][e.x.floor()] == 0 &&
            map[(fny + kER).floor()][e.x.floor()] == 0) e.y = fny;
        e.flinchVx *= (1.0 - dt * 12.0).clamp(0.0, 1.0);
        e.flinchVy *= (1.0 - dt * 12.0).clamp(0.0, 1.0);
        continue;
      }

      final nx = e.x + moveX * spd * dt;
      final ny = e.y + moveY * spd * dt;
      final nxOk = map[e.y.floor()][(nx - kER).floor()] == 0 &&
                   map[e.y.floor()][(nx + kER).floor()] == 0;
      final nyOk = map[(ny - kER).floor()][e.x.floor()] == 0 &&
                   map[(ny + kER).floor()][e.x.floor()] == 0;
      if (nxOk) e.x = nx;
      if (nyOk) e.y = ny;
      if (!nxOk && !nyOk) {
        e.stuckTimer += dt;
        if (e.stuckTimer > 0.4) { e.steerBias = -e.steerBias; e.stuckTimer = 0; }
        final px = -moveY * e.steerBias, py = moveX * e.steerBias;
        final snx = e.x + px * spd * dt, sny = e.y + py * spd * dt;
        if (map[e.y.floor()][(snx-kER).floor()] == 0 &&
            map[e.y.floor()][(snx+kER).floor()] == 0) e.x = snx;
        if (map[(sny-kER).floor()][e.x.floor()] == 0 &&
            map[(sny+kER).floor()][e.x.floor()] == 0) e.y = sny;
      } else {
        e.stuckTimer = (e.stuckTimer - dt * 3).clamp(0, 2);
      }
    }
    _separateEnemies(map);
  }

  void _separateEnemies(List<List<int>> map) {
    const double minDist = 0.62;
    const double kER = 0.30;
    final list = _enemies.where((e) => e.alive).toList();
    for (int i = 0; i < list.length; i++) {
      for (int j = i + 1; j < list.length; j++) {
        final a = list[i], b = list[j];
        if (a.isMega || b.isMega) continue;
        double dx = b.x - a.x, dy = b.y - a.y;
        final d2 = dx * dx + dy * dy;
        if (d2 >= minDist * minDist) continue;
        double d = sqrt(d2);
        if (d < 0.0001) {
          dx = _rng.nextDouble() - 0.5;
          dy = _rng.nextDouble() - 0.5;
          d = sqrt(dx * dx + dy * dy) + 0.0001;
        }
        final push = (minDist - d) * 0.5;
        final ux = dx / d, uy = dy / d;
        _nudgeEnemy(a, -ux * push, -uy * push, map, kER);
        _nudgeEnemy(b, ux * push, uy * push, map, kER);
      }
    }
  }

  void _nudgeEnemy(
      _Enemy e, double dx, double dy, List<List<int>> map, double kER) {
    final nx = e.x + dx;
    if (map[e.y.floor()][(nx - kER).floor()] == 0 &&
        map[e.y.floor()][(nx + kER).floor()] == 0) {
      e.x = nx;
    }
    final ny = e.y + dy;
    if (map[(ny - kER).floor()][e.x.floor()] == 0 &&
        map[(ny + kER).floor()][e.x.floor()] == 0) {
      e.y = ny;
    }
  }

  void _updateProjectiles(double dt) {
    final map = _currentMap;
    for (final p in _projectiles) {
      if (!p.alive) continue;
      p.x += p.dx * p.speed * dt;
      p.y += p.dy * p.speed * dt;
      p.dist += p.speed * dt;

      final mx = p.x.floor(), my = p.y.floor();
      if (mx < 0 || mx >= _kMapW || my < 0 || my >= _kMapH || map[my][mx] == 1) {
        p.alive = false;
        continue;
      }
      if (p.dist > _Projectile.maxRange) { p.alive = false; continue; }

      final pdx = _posX - p.x, pdy = _posY - p.y;
      if (pdx * pdx + pdy * pdy < 0.28 * 0.28) {
        p.alive = false;
        if (!_modGodMode) _health -= p.damage;
        _hitFlash = (_hitFlash + 0.55).clamp(0.0, 1.0);
        if (_damageCooldown <= 0) {
          HapticFeedback.lightImpact();
          _damageCooldown = 0.35;
        }
        if (_health <= 0) { _health = 0; _gameOver(); return; }
      }
    }
    _projectiles.removeWhere((p) => !p.alive);
  }

  void _updateTimers(double dt) {
    if (_damageCooldown > 0) _damageCooldown -= dt;
    if (_fireTimer > 0) _fireTimer -= dt;
    if (_hitFlash > 0) _hitFlash = (_hitFlash - dt * 2.5).clamp(0, 1);
    if (_shootFlash > 0) _shootFlash = (_shootFlash - dt * 10.0).clamp(0, 1);
    if (_waveBannerTimer > 0) _waveBannerTimer -= dt;
    if (_realmTransitionTimer > 0) _realmTransitionTimer -= dt;
    if (_dimFlash > 0) _dimFlash = (_dimFlash - dt * 1.8).clamp(0, 1);
    _dimTimer -= dt;
    if (_dimTimer <= 0) {
      _dimFlash = 0.08 + _rng.nextDouble() * 0.14;
      _dimTimer = 4.0 + _rng.nextDouble() * 6.0;
    }
    for (final e in _enemies) {
      if (e.hitFlash > 0) e.hitFlash = (e.hitFlash - dt * 7.0).clamp(0, 1);
      if (e.attackCooldown > 0) e.attackCooldown -= dt;
    }
  }

  void _checkRelic() {
    if (!_relicActive) return;
    final dx = _relicX - _posX, dy = _relicY - _posY;
    if (dx * dx + dy * dy < 0.6 * 0.6) {
      _relicActive = false;
      _health = (_health + 25).clamp(0, 100.0);
      HapticFeedback.heavyImpact();
    }
  }

  void _gameOver() {
    _gameTimer?.cancel();
    _state = _GameState.dead;
    HapticFeedback.heavyImpact();
    HighScoreService.submit('raycaster', _kills);
    HighScoreService.load('raycaster').then((v) => setState(() => _hiScore = v));
  }

  Future<void> _updateFirestore(double newSaldo) async {
    // Routes through the server-side `updateRewardsSaldo`
    // callable instead of writing rewards/{docId} directly
    // (admin-only collection — direct writes failed silently
    // for every non-admin user). The CF resolves the wallet,
    // applies the delta in a transaction, and mirrors the
    // result to the owner-readable card cache.
    final delta = newSaldo - _lastCommitted;
    if (delta == 0) return;
    final result = await applyArcadeDelta(
      delta: delta,
      reason: 'raycaster',
    );
    if (result != null) {
      _lastCommitted = result;
      if (mounted && _saldo != result) {
        setState(() => _saldo = result);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        SizedBox.expand(
          child: CustomPaint(
            painter: _RaycasterPainter(
              posX: _posX, posY: _posY,
              dirX: _dirX, dirY: _dirY,
              planeX: _planeX, planeY: _planeY,
              enemies: _enemies,
              projectiles: _projectiles,
              zBuf: _zBuf,
              health: _health.round().clamp(0, 100),
              kills: _kills,
              ammo: _ammo,
              shotgunAmmo: _shotgunAmmo,
              shotgunUnlocked: _shotgunUnlocked,
              smgAmmo: _smgAmmo,
              smgUnlocked: _smgUnlocked,
              weapon: _weapon,
              wave: _wave,
              hitFlash: _hitFlash,
              shootFlash: _shootFlash,
              dimFlash: _dimFlash,
              isFiring: _fireTimer > 0,
              showHud: _state == _GameState.playing || _state == _GameState.dead,
              time: _time,
              relicActive: _relicActive,
              relicX: _relicX,
              relicY: _relicY,
              currentMap: _currentMap,
              realmIdx: _currentRealm,
              megaAlive: _megaAlive,
              language: widget.language,
            ),
          ),
        ),
        if (_state == _GameState.playing && _waveBannerTimer > 0) _buildWaveBanner(),
        if (_state == _GameState.start)  _buildStartOverlay(),
        if (_state == _GameState.dead)   _buildDeathOverlay(),
        if (_paused && _state == _GameState.playing) _buildPauseOverlay(),
        if (_isAdmin && _modMenuOpen) _buildModMenu(),
      ]),
    );
  }

  Widget _buildWaveBanner() {
    final isBoss = _wave % 5 == 0;
    final isRealm = _realmTransitionTimer > 0 && _waveBannerTimer > 0;
    final borderColor = isRealm
        ? const Color(0xFF00DDFF)
        : isBoss ? const Color(0xFFFF6600) : const Color(0xFFCC2200);
    final titleColor = isRealm
        ? const Color(0xFF00FFDD)
        : isBoss ? const Color(0xFFFF8800) : Colors.white;
    final subColor = isRealm
        ? const Color(0xFF0099BB)
        : isBoss ? const Color(0xFFFF4400) : const Color(0xFFAA4422);

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.90),
          border: Border.all(color: borderColor, width: isRealm ? 3 : (isBoss ? 3 : 2)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRealm) ...[
              Text('🌀  ${_t('NUEVO REINO', 'NEW REALM')}  🌀',
                style: const TextStyle(
                  color: Color(0xFF00FFDD), fontSize: 24,
                  fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 3)),
              const SizedBox(height: 4),
              Text((widget.language == AppLanguage.spanish ? _kRealmNames : _kRealmNamesEn)[_currentRealm],
                style: const TextStyle(
                  color: Color(0xFFAAFFFF), fontSize: 18,
                  fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 2)),
              const SizedBox(height: 4),
              Text((widget.language == AppLanguage.spanish ? _kRealmTaglines : _kRealmTaglinesEn)[_currentRealm],
                style: const TextStyle(
                  color: Color(0xFF006688), fontSize: 11, fontFamily: 'monospace')),
            ] else ...[
              Text(
                isBoss
                    ? '⚡ ${_t('OLEADA JEFE', 'BOSS WAVE')} $_wave ⚡'
                    : '${_t('¡OLEADA', 'WAVE')} $_wave${_t('!', '!')}',
                style: TextStyle(
                  color: titleColor,
                  fontSize: isBoss ? 30 : 36,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  letterSpacing: 4,
                ),
              ),
              if (_waveFlavorText.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  _waveFlavorText,
                  style: TextStyle(color: subColor, fontSize: 12, fontFamily: 'monospace', letterSpacing: 1),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStartOverlay() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF0100000), Color(0xF0200000)],
        ),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🔥', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 8),
          Text(_t('CRIPTA MALDITA', 'CRYPT DOOM'),
            style: const TextStyle(
              color: Color(0xFFCC2200),
              fontSize: 26,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              letterSpacing: 3,
            )),
          const SizedBox(height: 4),
          Text(_t('Los demonios te esperan en las sombras…',
                  'Demons await you in the shadows…'),
            style: const TextStyle(color: Color(0xFF882200), fontSize: 11, fontFamily: 'monospace')),
          const SizedBox(height: 22),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF660000), width: 1),
              color: const Color(0x33110000),
            ),
            child: Column(children: [
              Text(_t('↑↓ mover   ←→ girar   A disparar',
                      '↑↓ move   ←→ turn   A shoot'),
                style: const TextStyle(color: Color(0xFF44FF00), fontSize: 12, fontFamily: 'monospace')),
              const SizedBox(height: 6),
              Text(_t('B: cambiar arma   (desbloquea escopeta/SMG)',
                      'B: cycle weapon   (unlock shotgun/SMG)'),
                style: const TextStyle(color: Color(0xFF888888), fontSize: 10, fontFamily: 'monospace')),
              const SizedBox(height: 8),
              Text(_t('BAJAS × OLEADA = PUNTUACIÓN',
                      'KILLS × WAVE = SCORE'),
                style: const TextStyle(color: Color(0xFFCC8800), fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
              Text(_t('+1 PTO CADA OLEADA   JEFE CADA 5ª',
                      '+1 PT PER WAVE   BOSS EVERY 5th'),
                style: const TextStyle(color: Color(0xFFFF4400), fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
              Text(_t('✨ Relicarios curan +25 HP cada 3 oleadas',
                      '✨ Relics heal +25 HP every 3 waves'),
                style: const TextStyle(color: Color(0xFF44FF88), fontSize: 9, fontFamily: 'monospace')),
            ]),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: _startGame,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B0000),
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder()),
                child: Text('⚔  ${_t('Entrar a la Mazmorra', 'Enter the Dungeon')}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              )),
          ),
        ]),
      ),
    );
  }

  Widget _buildDeathOverlay() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF0200000), Color(0xF0050000)],
        ),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('💀', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 8),
          Text(_t('HAS CAÍDO', 'YOU FELL'),
            style: const TextStyle(
              color: Color(0xFFFF2200),
              fontSize: 30,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              letterSpacing: 3,
            )),
          const SizedBox(height: 4),
          Text(_t('Los demonios han terminado contigo',
                  'The demons have finished you'),
            style: const TextStyle(color: Color(0xFF882200), fontSize: 11, fontFamily: 'monospace')),
          const SizedBox(height: 20),
          Text('${_t('Bajas', 'Kills')}: $_kills',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          Text('${_t('Oleada alcanzada', 'Wave reached')}: $_wave',
            style: const TextStyle(color: Color(0xFFFF8800), fontSize: 14, fontFamily: 'monospace')),
          Text('${_t('Récord', 'Record')}: $_hiScore ${_t('bajas', 'kills')}',
            style: const TextStyle(color: Color(0xFFFFDD00), fontSize: 12, fontFamily: 'monospace')),
          const SizedBox(height: 26),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: _restart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B0000),
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder()),
                child: Text('⚔  ${_t('Nueva Batalla', 'New Battle')}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              )),
          ),
        ]),
      ),
    );
  }

  Widget _buildPauseOverlay() => Positioned.fill(
    child: Container(
      color: const Color(0xCC000000),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('⏸', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 8),
          Text(_t('PAUSA', 'PAUSE'), style: const TextStyle(color: Color(0xFFFF4422), fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 6)),
          const SizedBox(height: 16),
          Text(_t('START para continuar', 'Press START to continue'), style: const TextStyle(color: Color(0xFF882211), fontSize: 12)),
        ],
      ),
    ),
  );

  Widget _buildModMenu() {
    final labels = widget.language == AppLanguage.spanish
        ? ['MUNICIÓN INFINITA', 'AIMBOT', 'MODO DIOS', 'MUERTE INSTANTÁNEA']
        : ['INFINITE AMMO', 'AIMBOT', 'GOD MODE', 'INSTANT KILL'];
    final values = [_modUnlimitedAmmo, _modAimbot, _modGodMode, _modInstantKill];
    return Positioned.fill(
      child: Container(
        color: const Color(0xE5000000),
        child: Center(
          child: Container(
            width: 240,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0A),
              border: Border.all(color: const Color(0xFFCC2200), width: 2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('— CHEAT MENU —',
                style: TextStyle(color: Color(0xFFCC2200), fontSize: 12,
                    fontWeight: FontWeight.bold, fontFamily: 'monospace',
                    letterSpacing: 2)),
              const SizedBox(height: 12),
              ...List.generate(4, (i) {
                final selected = _modCursor == i;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Text(selected ? '▶ ' : '  ',
                      style: const TextStyle(color: Color(0xFFFF4400), fontSize: 12,
                          fontFamily: 'monospace')),
                    Expanded(
                      child: Text(labels[i],
                        style: TextStyle(
                          color: selected ? Colors.white : const Color(0xFF888888),
                          fontSize: 11, fontFamily: 'monospace',
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                        )),
                    ),
                    Text(values[i] ? 'ON ' : 'OFF',
                      style: TextStyle(
                        color: values[i] ? const Color(0xFF44FF44) : const Color(0xFF884444),
                        fontSize: 11, fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      )),
                  ]),
                );
              }),
              const SizedBox(height: 12),
              const Text('↑↓ navegar  A activar  B cerrar',
                style: TextStyle(color: Color(0xFF444444), fontSize: 9,
                    fontFamily: 'monospace')),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RaycasterPainter extends CustomPainter {
  final double posX, posY, dirX, dirY, planeX, planeY;
  final List<_Enemy> enemies;
  final List<_Projectile> projectiles;
  final List<double> zBuf;
  final int health, kills, ammo, shotgunAmmo, smgAmmo, wave;
  final bool shotgunUnlocked, smgUnlocked;
  final _WeaponType weapon;
  final double hitFlash, shootFlash, dimFlash, time;
  final bool isFiring, showHud;
  final bool relicActive;
  final double relicX, relicY;
  final List<List<int>> currentMap;
  final int realmIdx;
  final bool megaAlive;
  final AppLanguage language;

  const _RaycasterPainter({
    required this.posX, required this.posY,
    required this.dirX, required this.dirY,
    required this.planeX, required this.planeY,
    required this.enemies, required this.projectiles, required this.zBuf,
    required this.health, required this.kills,
    required this.ammo, required this.shotgunAmmo,
    required this.shotgunUnlocked,
    required this.smgAmmo, required this.smgUnlocked,
    required this.weapon,
    required this.wave,
    required this.hitFlash, required this.shootFlash,
    required this.dimFlash,
    required this.isFiring, required this.showHud,
    required this.time,
    required this.relicActive,
    required this.relicX, required this.relicY,
    required this.currentMap,
    required this.realmIdx,
    required this.megaAlive,
    this.language = AppLanguage.spanish,
  });

  @override
  bool shouldRepaint(_RaycasterPainter old) => true;

  String _pt(String es, String en) =>
      language == AppLanguage.spanish ? es : en;

  @override
  void paint(Canvas canvas, Size size) {
    const numCols = 240;
    final pxW = size.width / numCols;
    final pxH = size.height / 80.0;

    _drawCeilingAndFloor(canvas, size, pxW, pxH);
    _castWalls(canvas, size, pxW, pxH);
    _drawEnemySprites(canvas, size, pxW, pxH);
    _drawProjectiles(canvas, size, pxW, pxH);
    if (relicActive) _drawRelic(canvas, size, pxW, pxH);
    _drawScreenFx(canvas, size);
    if (showHud) {
      _drawHud(canvas, size);
      _drawCrosshair(canvas, size);
      _drawWeapon(canvas, size, isFiring);
      if (!megaAlive) _drawRadar(canvas, size);
    }
  }

  void _drawCeilingAndFloor(Canvas canvas, Size size, double pxW, double pxH) {
    final p = Paint()..isAntiAlias = false;
    final cH = size.height / 2;
    final fY = size.height / 2;

    final ceilingBands = switch (realmIdx) {
      1 => const [
        (0.00, 0.10, Color(0xFF020308)),
        (0.10, 0.25, Color(0xFF05070F)),
        (0.25, 0.45, Color(0xFF0A0E1F)),
        (0.45, 0.65, Color(0xFF121830)),
        (0.65, 0.82, Color(0xFF1A2240)),
        (0.82, 1.00, Color(0xFF222D52)),
      ],
      2 => const [
        (0.00, 0.10, Color(0xFF060009)),
        (0.10, 0.25, Color(0xFF0D0016)),
        (0.25, 0.45, Color(0xFF1A0028)),
        (0.45, 0.65, Color(0xFF27003C)),
        (0.65, 0.82, Color(0xFF370054)),
        (0.82, 1.00, Color(0xFF48006E)),
      ],
      3 => const [
        (0.00, 0.10, Color(0xFF160300)),
        (0.10, 0.25, Color(0xFF300700)),
        (0.25, 0.45, Color(0xFF580F00)),
        (0.45, 0.65, Color(0xFF7E1900)),
        (0.65, 0.82, Color(0xFFAA2800)),
        (0.82, 1.00, Color(0xFFCC3C00)),
      ],
      _ => const [
        (0.00, 0.10, Color(0xFF100200)),
        (0.10, 0.25, Color(0xFF2B0600)),
        (0.25, 0.45, Color(0xFF4C0B00)),
        (0.45, 0.65, Color(0xFF6E1400)),
        (0.65, 0.82, Color(0xFF902200)),
        (0.82, 1.00, Color(0xFFAE3500)),
      ],
    };
    for (final band in ceilingBands) {
      p.color = band.$3;
      canvas.drawRect(Rect.fromLTWH(0, cH * band.$1, size.width, cH * (band.$2 - band.$1) + 1), p);
    }

    final floorBands = switch (realmIdx) {
      1 => const [
        (0.00, 0.06, Color(0xFF3A4880)),
        (0.06, 0.16, Color(0xFF252F55)),
        (0.16, 0.32, Color(0xFF16203A)),
        (0.32, 0.55, Color(0xFF0D1428)),
        (0.55, 0.78, Color(0xFF07091A)),
        (0.78, 1.00, Color(0xFF03040D)),
      ],
      2 => const [
        (0.00, 0.06, Color(0xFF5A00AA)),
        (0.06, 0.16, Color(0xFF3C0072)),
        (0.16, 0.32, Color(0xFF250048)),
        (0.32, 0.55, Color(0xFF160030)),
        (0.55, 0.78, Color(0xFF0A001C)),
        (0.78, 1.00, Color(0xFF05000E)),
      ],
      3 => const [
        (0.00, 0.06, Color(0xFF9E3000)),
        (0.06, 0.16, Color(0xFF6A1E00)),
        (0.16, 0.32, Color(0xFF3E1000)),
        (0.32, 0.55, Color(0xFF260A00)),
        (0.55, 0.78, Color(0xFF160500)),
        (0.78, 1.00, Color(0xFF0A0200)),
      ],
      _ => const [
        (0.00, 0.06, Color(0xFF7A3C14)),
        (0.06, 0.16, Color(0xFF502200)),
        (0.16, 0.32, Color(0xFF321400)),
        (0.32, 0.55, Color(0xFF200C00)),
        (0.55, 0.78, Color(0xFF130600)),
        (0.78, 1.00, Color(0xFF080300)),
      ],
    };
    for (final band in floorBands) {
      p.color = band.$3;
      canvas.drawRect(Rect.fromLTWH(0, fY + cH * band.$1, size.width, cH * (band.$2 - band.$1) + 1), p);
    }

    final horizonColor = switch (realmIdx) {
      1 => const Color(0xFF6070CC),
      2 => const Color(0xFF9933FF),
      3 => const Color(0xFFFF6622),
      _ => const Color(0xFFCC6622),
    };
    p.color = horizonColor.withOpacity(0.55);
    canvas.drawRect(Rect.fromLTWH(0, fY - 1.0, size.width, 2.0), p);
    final hGlowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [horizonColor.withOpacity(0.28), const Color(0x00000000)],
      ).createShader(Rect.fromLTWH(0, fY, size.width, cH * 0.10));
    canvas.drawRect(Rect.fromLTWH(0, fY, size.width, cH * 0.10), hGlowPaint);

    p.color = const Color(0xFF2A0400);
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.82, size.width * 0.12, size.height * 0.08), p);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.55, size.height * 0.88, size.width * 0.18, size.height * 0.06), p);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.78, size.height * 0.80, size.width * 0.10, size.height * 0.10), p);

    for (int streak = 0; streak < 4; streak++) {
      final streakX = size.width * (0.12 + streak * 0.22 + sin(time * 0.25 + streak * 1.7) * 0.04);
      final streakW = size.width * (0.07 + sin(time * 0.6 + streak * 2.3) * 0.02);
      final lavaOp = (0.08 + sin(time * 1.8 + streak * 1.1) * 0.05).clamp(0.03, 0.18);
      final lp = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [
            const Color(0x00FF4400),
            Color.fromARGB((lavaOp * 255).round(), 0xFF, streak.isEven ? 0x66 : 0x33, 0x00),
          ],
        ).createShader(Rect.fromLTWH(streakX, fY, streakW, size.height - fY));
      canvas.drawRect(Rect.fromLTWH(streakX, fY, streakW, size.height - fY), lp);
    }

    final fireOpacity = (0.22 + sin(time * 1.4) * 0.07).clamp(0.12, 0.38);
    final fireColor = Color.fromARGB((fireOpacity * 255).round(), 0xCC, 0x11, 0x00);
    final vPaint = Paint()
      ..shader = LinearGradient(
        colors: [fireColor, const Color(0x00000000)],
      ).createShader(Rect.fromLTWH(0, 0, size.width * 0.22, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width * 0.22, size.height), vPaint);

    final vPaint2 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
        colors: [fireColor, const Color(0x00000000)],
      ).createShader(Rect.fromLTWH(size.width * 0.78, 0, size.width * 0.22, size.height));
    canvas.drawRect(Rect.fromLTWH(size.width * 0.78, 0, size.width * 0.22, size.height), vPaint2);

    final topFire = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.fromARGB((fireOpacity * 180).round(), 0x88, 0x08, 0x00), const Color(0x00000000)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.15));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height * 0.15), topFire);

    final botFire = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [Color.fromARGB((fireOpacity * 200).round(), 0xAA, 0x10, 0x00), const Color(0x00000000)],
      ).createShader(Rect.fromLTWH(0, size.height * 0.85, size.width, size.height * 0.15));
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.85, size.width, size.height * 0.15), botFire);
  }

  void _castWalls(Canvas canvas, Size size, double pxW, double pxH) {
    final wallPaint = Paint()..isAntiAlias = false;
    const numCols = 240;
    final halfH = size.height * 0.5;

    for (int x = 0; x < numCols; x++) {
      final cameraX = 2.0 * x / numCols - 1.0;
      final rayDirX = dirX + planeX * cameraX;
      final rayDirY = dirY + planeY * cameraX;

      int mapX = posX.floor(), mapY = posY.floor();

      final deltaDistX = rayDirX.abs() < 1e-20 ? 1e30 : 1.0 / rayDirX.abs();
      final deltaDistY = rayDirY.abs() < 1e-20 ? 1e30 : 1.0 / rayDirY.abs();

      int stepX, stepY;
      double sideDistX, sideDistY;

      if (rayDirX < 0) {
        stepX = -1; sideDistX = (posX - mapX) * deltaDistX;
      } else {
        stepX = 1; sideDistX = (mapX + 1.0 - posX) * deltaDistX;
      }
      if (rayDirY < 0) {
        stepY = -1; sideDistY = (posY - mapY) * deltaDistY;
      } else {
        stepY = 1; sideDistY = (mapY + 1.0 - posY) * deltaDistY;
      }

      int side = 0;
      int safety = 0;
      while (safety++ < 100) {
        if (sideDistX < sideDistY) {
          sideDistX += deltaDistX; mapX += stepX; side = 0;
        } else {
          sideDistY += deltaDistY; mapY += stepY; side = 1;
        }
        if (mapX < 0 || mapX >= _kMapW || mapY < 0 || mapY >= _kMapH) break;
        if (currentMap[mapY][mapX] == 1) break;
      }

      final perpWallDist = side == 0 ? sideDistX - deltaDistX : sideDistY - deltaDistY;
      zBuf[x] = perpWallDist;

      final wallHPx = (size.height / perpWallDist).clamp(0.5, size.height * 4.0);
      final dsY = (halfH - wallHPx * 0.5).clamp(0.0, size.height);
      final deY = (halfH + wallHPx * 0.5).clamp(0.0, size.height);
      final sliceH = (deY - dsY).clamp(0.5, size.height);

      final isBoundary = (mapX == 0 || mapX == _kMapW - 1 || mapY == 0 || mapY == _kMapH - 1);
      if (isBoundary) {
        final br = (1.0 / (1.0 + perpWallDist * 0.18)).clamp(0.04, 1.0);
        double bWallX;
        if (side == 0) {
          bWallX = posY + perpWallDist * rayDirY;
        } else {
          bWallX = posX + perpWallDist * rayDirX;
        }
        bWallX -= bWallX.floor();

        final jag1 = sin(bWallX * pi * 9.7)  * 0.22;
        final jag2 = sin(bWallX * pi * 17.3) * 0.11;
        final pileH = (sliceH / 3.0) * (0.70 + (jag1 + jag2).abs() * 0.60)
            .clamp(0.30, 1.50);
        final pileTop = deY - pileH;

        if (pileH < 0.5) continue;

        wallPaint.color = Color.fromRGBO(0x10, 0x08, 0x04,
            (0.85 * br).clamp(0.0, 1.0));
        canvas.drawRect(Rect.fromLTWH(x * pxW, pileTop + pileH * 0.85,
            pxW + 0.5, pileH * 0.15 + 0.5), wallPaint);

        const kBoneLayers = 4;
        for (int bi = 0; bi < kBoneLayers; bi++) {
          final layerFrac = bi / kBoneLayers;
          final layerY = pileTop + pileH * layerFrac;
          final layerH  = (pileH / kBoneLayers) *
              (bi == kBoneLayers - 1 ? 0.55 : 0.85);

          final hash = ((bWallX * 13.7 + bi * 4.3 + mapX * 2.1 + mapY * 1.7)
              .abs() % 7).floor();
          final isGap = hash == 0;
          final isShadowed = hash <= 1;
          final shade = isGap ? 0.12 : (isShadowed ? 0.52 : (hash.isEven ? 1.0 : 0.78));

          final boneR = (0xD6 * br * shade).round().clamp(0, 255);
          final boneG = (0xC2 * br * shade).round().clamp(0, 255);
          final boneB = (0x82 * br * shade).round().clamp(0, 255);
          wallPaint.color = Color.fromRGBO(boneR, boneG, boneB, 1);
          canvas.drawRect(Rect.fromLTWH(
              x * pxW, layerY, pxW + 0.5, layerH + 0.5), wallPaint);
        }

        if (perpWallDist < 7.0) {
          final skullSlot = (bWallX * 5.0).floor();
          if (skullSlot % 5 == 0) {
            final eyeOp = (0.75 * br).clamp(0.0, 1.0);
            wallPaint.color = Color.fromRGBO(0x14, 0x0A, 0x04, eyeOp);
            final eyeY = pileTop + pileH * 0.12;
            final eyeH = pileH * 0.22;
            canvas.drawRect(Rect.fromLTWH(x * pxW, eyeY, pxW + 0.5, eyeH), wallPaint);
          }
        }
        continue;
      }

      final lavaTowers = _kRealmLavaTowers[realmIdx.clamp(0, _kRealmLavaTowers.length - 1)];
      final isLavaTower = lavaTowers.any((t) => t[0] == mapX && t[1] == mapY);

      if (isLavaTower) {
        final br = (1.0 / (1.0 + perpWallDist * 0.22)).clamp(0.08, 1.0);
        final pulse = (0.7 + sin(time * 2.5 + mapX * 1.3 + mapY * 0.7) * 0.3).clamp(0.5, 1.0);
        wallPaint.color = Color.fromRGBO(
          (0xDD * br * pulse).round().clamp(0, 255),
          (0x33 * br * pulse).round().clamp(0, 255),
          0, 1);
        canvas.drawRect(Rect.fromLTWH(x * pxW, dsY, pxW + 0.5, sliceH), wallPaint);
        if (perpWallDist < 5.0) {
          wallPaint.color = Color.fromRGBO(255,
            (0x88 * pulse).round().clamp(0, 255),
            0, (0.6 * br).clamp(0, 1));
          canvas.drawRect(Rect.fromLTWH(x * pxW, dsY + sliceH * 0.25, pxW + 0.5, sliceH * 0.5), wallPaint);
        }
        continue;
      }

      final int baseR, baseG, baseB;
      switch (realmIdx) {
        case 1:
          baseR = side == 0 ? 0x44 : 0x2E;
          baseG = side == 0 ? 0x44 : 0x2E;
          baseB = side == 0 ? 0x66 : 0x44;
        case 2:
          baseR = side == 0 ? 0x55 : 0x38;
          baseG = side == 0 ? 0x10 : 0x08;
          baseB = side == 0 ? 0x55 : 0x38;
        case 3:
          baseR = side == 0 ? 0x88 : 0x5A;
          baseG = side == 0 ? 0x38 : 0x22;
          baseB = side == 0 ? 0x00 : 0x00;
        default:
          baseR = side == 0 ? 0x82 : 0x58;
          baseG = side == 0 ? 0x1E : 0x12;
          baseB = side == 0 ? 0x0A : 0x06;
      }

      final br = (1.0 / (1.0 + perpWallDist * 0.28)).clamp(0.08, 1.0);

      double wallX;
      if (side == 0) {
        wallX = posY + perpWallDist * rayDirY;
      } else {
        wallX = posX + perpWallDist * rayDirX;
      }
      wallX -= wallX.floor();
      final brickSeg = (wallX * 4).floor();
      final brickOff = (mapX * 3 + mapY * 7 + brickSeg) % 3;
      final brickTone = brickOff == 0 ? 1.14 : (brickOff == 1 ? 0.95 : 0.82);
      final adjBr = (br * brickTone).clamp(0.05, 1.0);

      wallPaint.color = Color.fromRGBO(
        (baseR * adjBr).round().clamp(0, 255),
        (baseG * adjBr).round().clamp(0, 255),
        (baseB * adjBr).round().clamp(0, 255), 1);
      canvas.drawRect(Rect.fromLTWH(x * pxW, dsY, pxW + 0.5, sliceH), wallPaint);

      if (perpWallDist < 4.0) {
        final edgeDist = (wallX * 4.0 - brickSeg.toDouble()).abs();
        if (edgeDist < 0.055) {
          wallPaint.color = Color.fromRGBO(
            (0x18 * br).round(), (0x04 * br).round(), (0x02 * br).round(), 1);
          canvas.drawRect(Rect.fromLTWH(x * pxW, dsY, pxW + 0.5, sliceH), wallPaint);
        }
      }
    }
  }

  void _drawEnemySprites(Canvas canvas, Size size, double pxW, double pxH) {
    final alive = enemies.where((e) => e.alive).toList();
    alive.sort((a, b) {
      final da = (a.x - posX) * (a.x - posX) + (a.y - posY) * (a.y - posY);
      final db = (b.x - posX) * (b.x - posX) + (b.y - posY) * (b.y - posY);
      return db.compareTo(da);
    });

    final sp = Paint()..isAntiAlias = false;
    const numCols = 240;
    final halfH = size.height * 0.5;

    for (final e in alive) {
      final dx = e.x - posX, dy = e.y - posY;
      final invDet = 1.0 / (planeX * dirY - dirX * planeY);
      final transformX = invDet * (dirY * dx - dirX * dy);
      final transformY = invDet * (-planeY * dx + planeX * dy);
      if (transformY <= 0.1) continue;

      final screenX = (numCols ~/ 2 * (1 + transformX / transformY)).round();

      final spriteHPx = (size.height / transformY * e.spriteScale).clamp(2.0, size.height * 0.92);
      final spriteWCols = (spriteHPx / pxW).round().clamp(2, numCols);

      final double bobOffsetPx;
      final double groundShiftPx;
      if (e.type == _EnemyType.cacodemon) {
        bobOffsetPx = sin(time * 2.8 + e.x * 1.3) * 3.0 * pxH;
        groundShiftPx = 0.0;
      } else {
        bobOffsetPx = 0.0;
        final scale = e.spriteScale;
        groundShiftPx = spriteHPx * (1.0 - scale) / (2.0 * scale);
      }

      final drawStartX = screenX - spriteWCols ~/ 2;
      final by = (halfH - spriteHPx * 0.5 + bobOffsetPx + groundShiftPx).clamp(0.0, size.height - 1.0);
      final endY = (halfH + spriteHPx * 0.5 + bobOffsetPx + groundShiftPx).clamp(1.0, size.height);
      final sh = endY - by;
      final v = sh / 20.0;
      final flash = e.hitFlash;

      for (int sx = drawStartX; sx < drawStartX + spriteWCols; sx++) {
        if (sx < 0 || sx >= numCols) continue;
        if (transformY >= zBuf[sx]) continue;

        final localX = sx - drawStartX;
        final frac = localX / spriteWCols.toDouble();

        switch (e.type) {
          case _EnemyType.demon:
            _drawDemonColumn(canvas, sp, sx, pxW, by, sh, v, frac, e.hp, flash, e.isMega, time);
          case _EnemyType.cacodemon:
            _drawCacoDemonColumn(canvas, sp, sx, pxW, by, sh, v, frac, e.hp, flash);
          case _EnemyType.skeleton:
            _drawSkeletonColumn(canvas, sp, sx, pxW, by, sh, v, frac, e.hp, flash, time);
          case _EnemyType.troll:
            _drawTrollColumn(canvas, sp, sx, pxW, by, sh, v, frac, e.hp, flash, e.teleportFlash, time);
        }
      }

      if (flash > 0.5) {
        final cx = screenX * pxW;
        final cy = by + sh * 0.5;
        sp.color = Colors.white;
        canvas.drawRect(Rect.fromLTWH(cx - 5, cy - 1, 10, 2), sp);
        canvas.drawRect(Rect.fromLTWH(cx - 1, cy - 5, 2, 10), sp);
      }
    }
  }

  void _drawProjectiles(Canvas canvas, Size size, double pxW, double pxH) {
    final sp = Paint()..isAntiAlias = false;
    final invDet = 1.0 / (planeX * dirY - dirX * planeY);
    const numCols = 240;

    for (final p in projectiles) {
      if (!p.alive) continue;
      final dx = p.x - posX, dy = p.y - posY;
      final transformX = invDet * (dirY * dx - dirX * dy);
      final transformY = invDet * (-planeY * dx + planeX * dy);
      if (transformY <= 0.05) continue;

      final screenCol = (numCols ~/ 2 * (1 + transformX / transformY)).round();
      if (screenCol < 0 || screenCol >= numCols) continue;
      if (transformY >= zBuf[screenCol]) continue;

      final screenX = screenCol * pxW;
      final screenY = size.height * 0.5;
      final s = (4.5 / transformY).clamp(1.0, 14.0);

      if (p.type == _EnemyType.troll) {
        final acidPulse = 0.7 + sin(time * 8.0 + p.x + p.y) * 0.3;
        sp.color = Color.fromARGB((0x33 * acidPulse).round(), 0x44, 0xFF, 0x00);
        canvas.drawCircle(Offset(screenX, screenY), s * pxW * 2.0, sp);
        sp.color = const Color(0xAA66FF22);
        canvas.drawCircle(Offset(screenX, screenY), s * pxW * 1.1, sp);
        sp.color = const Color(0xFFCCFF44);
        canvas.drawCircle(Offset(screenX, screenY), s * pxW * 0.5, sp);
        sp.color = Colors.white.withOpacity(0.6);
        canvas.drawCircle(Offset(screenX, screenY), s * pxW * 0.2, sp);
      } else if (p.type == _EnemyType.cacodemon) {
        sp.color = const Color(0x55FF2200);
        canvas.drawCircle(Offset(screenX, screenY), s * pxW * 1.5, sp);
        sp.color = Colors.orange;
        canvas.drawCircle(Offset(screenX, screenY), s * pxW * 0.9, sp);
        sp.color = const Color(0xFFFFEE44);
        canvas.drawCircle(Offset(screenX, screenY), s * pxW * 0.4, sp);
      } else {
        final hw = s * pxW * 1.2;
        final hh = s * pxH * 0.22;
        sp.color = const Color(0xFF8B5A2B);
        canvas.drawRect(Rect.fromCenter(
            center: Offset(screenX, screenY), width: hw * 2, height: hh * 2), sp);
        sp.color = const Color(0xFF888888);
        canvas.drawRect(Rect.fromCenter(
            center: Offset(screenX + hw * 0.65, screenY),
            width: hw * 0.7, height: hh * 3), sp);
      }
    }
  }

  void _drawDemonColumn(Canvas canvas, Paint sp, int sx, double pxW,
      double by, double sh, double v, double frac, double hp, double flash,
      [bool isMega = false, double time = 0]) {
    if (isMega) {
      _drawMegaDemonColumn(canvas, sp, sx, pxW, by, sh, v, frac, hp, flash);
      return;
    }
    const kPad = 0.10;
    if (v < 0.01) return;
    double vy(double row) => by + v * (kPad * 20 + row * 0.80);
    double vh(double rows) => v * rows * 0.80;

    final walkCycle = sin(time * 5.5);

    final Color body, detail, eye, mouth;
    if (hp >= 3) {
      body   = Color.fromARGB(255, (0x7A + (255 - 0x7A) * flash).round(), (0x10 * (1 - flash)).round(), (0x10 * (1 - flash)).round());
      detail = const Color(0xFF2A0404);
      eye    = const Color(0xFFFF2200);
      mouth  = const Color(0xFFFF6600);
    } else if (hp >= 2) {
      body   = Color.fromARGB(255, (0xAA + (255 - 0xAA) * flash).round(), (0x33 * (1 - flash)).round(), 0);
      detail = const Color(0xFF441800);
      eye    = const Color(0xFFFFAA00);
      mouth  = const Color(0xFFFF4400);
    } else {
      body   = Color.fromARGB(255, 255, (0x18 * (1 - flash)).round(), (0x88 * (1 - flash)).round());
      detail = const Color(0xFF660033);
      eye    = const Color(0xFFFF00FF);
      mouth  = const Color(0xFFFF00AA);
    }

    final x = sx * pxW;

    if ((frac >= 0.08 && frac <= 0.28) || (frac >= 0.72 && frac <= 0.92)) {
      sp.color = detail;
      canvas.drawRect(Rect.fromLTWH(x, vy(0), pxW, vh(3.0)), sp);
      sp.color = Color.fromARGB(255, (detail.red * 1.8).clamp(0,255).round(), 0, 0);
      canvas.drawRect(Rect.fromLTWH(x, vy(0), pxW, vh(0.5)), sp);
    }

    if (frac >= 0.22 && frac <= 0.78) {
      sp.color = body;
      canvas.drawRect(Rect.fromLTWH(x, vy(1), pxW, vh(4.0)), sp);
    }

    if ((frac >= 0.30 && frac <= 0.43) || (frac >= 0.57 && frac <= 0.70)) {
      sp.color = eye;
      canvas.drawRect(Rect.fromLTWH(x, vy(1.8), pxW, vh(1.8)), sp);
      sp.color = Colors.white.withOpacity(0.85);
      canvas.drawRect(Rect.fromLTWH(x, vy(2.1), pxW, vh(0.8)), sp);
    }

    if (frac >= 0.34 && frac <= 0.66) {
      sp.color = mouth;
      canvas.drawRect(Rect.fromLTWH(x, vy(3.8), pxW, vh(0.7)), sp);
      if (frac >= 0.36 && frac <= 0.40 || frac >= 0.48 && frac <= 0.52 ||
          frac >= 0.60 && frac <= 0.64) {
        sp.color = Colors.white.withOpacity(0.90);
        canvas.drawRect(Rect.fromLTWH(x, vy(4.2), pxW, vh(0.5)), sp);
      }
    }

    if (frac >= 0.42 && frac <= 0.58) {
      sp.color = Color.fromARGB(255, (body.red * 1.15).clamp(0,255).round(), 0, 0);
      canvas.drawRect(Rect.fromLTWH(x, vy(4.8), pxW, vh(1.2)), sp);
    }

    if (frac >= 0.18 && frac <= 0.82) {
      sp.color = body;
      canvas.drawRect(Rect.fromLTWH(x, vy(5), pxW, vh(9)), sp);
    }

    if ((frac >= 0.20 && frac <= 0.36) || (frac >= 0.64 && frac <= 0.80)) {
      sp.color = Color.fromARGB(255, (body.red * 1.70).clamp(0,255).round(), 0, 0);
      canvas.drawRect(Rect.fromLTWH(x, vy(5.2), pxW, vh(0.9)), sp);
      sp.color = Color.fromARGB(255, (body.red * 0.22).clamp(0,255).round(), 0, 0);
      canvas.drawRect(Rect.fromLTWH(x, vy(6.1), pxW, vh(0.9)), sp);
    }

    if (frac >= 0.46 && frac <= 0.54) {
      sp.color = Color.fromARGB(255, (body.red * 0.15).clamp(0,255).round(), 0, 0);
      canvas.drawRect(Rect.fromLTWH(x, vy(5), pxW, vh(3)), sp);
    }

    if (frac >= 0.30 && frac <= 0.70) {
      for (int ab = 0; ab < 4; ab++) {
        sp.color = ab.isEven
            ? Color.fromARGB(255, (body.red * 1.70).clamp(0,255).round(), 0, 0)
            : Color.fromARGB(255, (body.red * 0.18).clamp(0,255).round(), 0, 0);
        canvas.drawRect(Rect.fromLTWH(x, vy(7.5 + ab * 1.5), pxW, vh(1.0)), sp);
      }
    }

    if ((frac >= 0.16 && frac <= 0.20) || (frac >= 0.80 && frac <= 0.84)) {
      sp.color = Color.fromARGB(255, (body.red * 0.12).clamp(0,255).round(), 0, 0);
      canvas.drawRect(Rect.fromLTWH(x, vy(5), pxW, vh(9)), sp);
    }

    if ((frac >= 0.26 && frac <= 0.42) || (frac >= 0.58 && frac <= 0.74)) {
      final isLeft = frac <= 0.50;
      final legOff  = (isLeft ? walkCycle : -walkCycle) * vh(1.8);
      sp.color = body;
      canvas.drawRect(Rect.fromLTWH(x, vy(14) + legOff, pxW, vh(6)), sp);
      sp.color = Color.fromARGB(255, (body.red * 1.40).clamp(0, 255).round(), 0, 0);
      canvas.drawRect(Rect.fromLTWH(x, vy(15.5) + legOff, pxW, vh(1.0)), sp);
    }
    if ((frac >= 0.02 && frac <= 0.18) || (frac >= 0.82 && frac <= 0.98)) {
      final isLeft = frac <= 0.50;
      final armOff = (isLeft ? -walkCycle : walkCycle) * vh(1.5);
      sp.color = detail;
      canvas.drawRect(Rect.fromLTWH(x, vy(5) + armOff, pxW, vh(9)), sp);
      if ((frac >= 0.02 && frac <= 0.10) || (frac >= 0.90 && frac <= 0.98)) {
        sp.color = Color.fromARGB(255, (body.red * 1.55).clamp(0,255).round(), 0, 0);
        canvas.drawRect(Rect.fromLTWH(x, vy(5.5) + armOff, pxW, vh(4)), sp);
      }
      sp.color = Colors.white.withOpacity(0.80);
      canvas.drawRect(Rect.fromLTWH(x, vy(12.5) + armOff, pxW, vh(1.5)), sp);
    }
  }

  void _drawMegaDemonColumn(Canvas canvas, Paint sp, int sx, double pxW,
      double by, double sh, double v, double frac, double hp, double flash) {
    if (v < 0.01) return;
    final x = sx * pxW;

    final bodyR = (0x28 + (0xDD - 0x28) * flash).round().clamp(0, 255);
    final bodyB = (0x55 + (0xFF - 0x55) * flash).round().clamp(0, 255);
    final body   = Color.fromARGB(255, bodyR, 0x00, bodyB);
    final detail = const Color(0xFF0A0030);
    final eyeGlow  = const Color(0xFF00FF88);
    final eyeCore  = const Color(0xFFCCFFAA);
    final mouthCol = const Color(0xFFFF00FF);
    final accentCol = const Color(0xFF8800FF);

    final spikePositions = [0.05, 0.20, 0.38, 0.56, 0.74, 0.90];
    for (final sp0 in spikePositions) {
      final dist = (frac - sp0).abs();
      if (dist < 0.075) {
        final spikeH = v * (3.5 - dist * 30.0).clamp(0.5, 3.5);
        sp.color = detail;
        canvas.drawRect(Rect.fromLTWH(x, by, pxW, spikeH), sp);
        sp.color = accentCol;
        canvas.drawRect(Rect.fromLTWH(x, by, pxW, spikeH * 0.3), sp);
      }
    }

    if (frac >= 0.12 && frac <= 0.88) {
      sp.color = body;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 1.5, pxW, v * 5.0), sp);
    }

    final eyePairs = [
      [0.18, 0.30], [0.36, 0.48], [0.52, 0.64], [0.70, 0.82],
    ];
    for (final pair in eyePairs) {
      if (frac >= pair[0] && frac <= pair[1]) {
        sp.color = eyeGlow;
        canvas.drawRect(Rect.fromLTWH(x, by + v * 2.5, pxW, v * 1.5), sp);
        sp.color = eyeCore;
        canvas.drawRect(Rect.fromLTWH(x, by + v * 2.8, pxW, v * 0.7), sp);
      }
    }

    if ((frac >= 0.30 && frac <= 0.36) || (frac >= 0.48 && frac <= 0.52) ||
        (frac >= 0.64 && frac <= 0.70)) {
      sp.color = detail;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 2.2, pxW, v * 2.5), sp);
    }

    if (frac >= 0.18 && frac <= 0.82) {
      sp.color = mouthCol;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 5.0, pxW, v * 1.8), sp);
      final toothIdx = ((frac - 0.18) / 0.64 * 10).floor();
      if (toothIdx % 2 == 0) {
        sp.color = Colors.white;
        canvas.drawRect(Rect.fromLTWH(x, by + v * 6.2, pxW, v * 0.9), sp);
      }
    }
    if (frac >= 0.18 && frac <= 0.82) {
      sp.color = const Color(0xFF0A0000);
      canvas.drawRect(Rect.fromLTWH(x, by + v * 5.3, pxW, v * 0.8), sp);
    }

    if (frac >= 0.38 && frac <= 0.62) {
      sp.color = Color.fromARGB(255, bodyR, 0, (bodyB * 0.7).round());
      canvas.drawRect(Rect.fromLTWH(x, by + v * 6.5, pxW, v * 1.0), sp);
    }

    if (frac >= 0.06 && frac <= 0.94) {
      sp.color = body;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 7.5, pxW, v * 8.5), sp);
    }

    for (int band = 0; band < 4; band++) {
      if (frac >= 0.10 && frac <= 0.90) {
        sp.color = band.isEven ? accentCol.withOpacity(0.7) : detail;
        canvas.drawRect(Rect.fromLTWH(x, by + v * (8.5 + band * 1.8), pxW, v * 0.55), sp);
      }
    }

    if (frac >= 0.46 && frac <= 0.54) {
      sp.color = accentCol;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 7.5, pxW, v * 7.5), sp);
    }

    if ((frac >= 0.12 && frac <= 0.30) || (frac >= 0.70 && frac <= 0.88)) {
      sp.color = Color.fromARGB(255, (bodyR * 1.9).clamp(0, 255).round(), 0, (bodyB * 1.6).clamp(0, 255).round());
      canvas.drawRect(Rect.fromLTWH(x, by + v * 7.8, pxW, v * 1.0), sp);
    }

    if ((frac >= 0.01 && frac <= 0.06) || (frac >= 0.94 && frac <= 0.99)) {
      sp.color = detail;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 5.0, pxW, v * 11.0), sp);
      sp.color = Color.fromARGB(255, 0, 0, (bodyB * 1.8).clamp(0, 255).round());
      canvas.drawRect(Rect.fromLTWH(x, by + v * 6.0, pxW, v * 5.0), sp);
      sp.color = eyeCore;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 14.0, pxW, v * 2.0), sp);
    }

    if ((frac >= 0.22 && frac <= 0.40) || (frac >= 0.60 && frac <= 0.78)) {
      sp.color = body;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 16.0, pxW, v * 4.0), sp);
      sp.color = Color.fromARGB(255, (bodyR * 1.6).clamp(0, 255).round(), 0, bodyB);
      canvas.drawRect(Rect.fromLTWH(x, by + v * 17.0, pxW, v * 1.2), sp);
    }

    if (frac < 0.06 || frac > 0.94) {
      sp.color = accentCol.withOpacity(0.30 * flash.clamp(0.1, 1.0) + 0.15);
      canvas.drawRect(Rect.fromLTWH(x, by + v * 3.0, pxW, v * 14.0), sp);
    }
  }

  void _drawCacoDemonColumn(Canvas canvas, Paint sp, int sx, double pxW,
      double by, double sh, double v, double frac, double hp, double flash) {
    final xFrac = frac - 0.5;
    if (xFrac.abs() >= 0.5) return;

    final sphereRadius = sqrt(0.25 - xFrac * xFrac);
    final sphereTop = by + sh * (0.5 - sphereRadius);
    final sphereBot = by + sh * (0.5 + sphereRadius);
    final spriteH = sphereBot - sphereTop;
    final x = sx * pxW;

    final edgeFactor = xFrac.abs() * 2.0;
    final shade = (1.0 - edgeFactor * 0.55).clamp(0.35, 1.0);

    final Color bodyBase;
    if (hp >= 2) {
      bodyBase = Color.fromARGB(255,
          (0xAA + (255 - 0xAA) * flash).round().clamp(0, 255),
          (0x0A * (1 - flash)).round().clamp(0, 255),
          (0x0A * (1 - flash)).round().clamp(0, 255));
    } else {
      bodyBase = Color.fromARGB(255,
          (0x88 + (255 - 0x88) * flash).round().clamp(0, 255),
          (0x04 * (1 - flash)).round().clamp(0, 255),
          (0x22 * (1 - flash)).round().clamp(0, 255));
    }

    sp.color = Color.fromARGB(255,
        (bodyBase.red   * shade).round().clamp(0, 255),
        (bodyBase.green * shade).round().clamp(0, 255),
        (bodyBase.blue  * shade).round().clamp(0, 255));
    canvas.drawRect(Rect.fromLTWH(x, sphereTop, pxW, spriteH), sp);

    if (xFrac.abs() < 0.45) {
      final veinY = sphereTop + spriteH * 0.60;
      sp.color = const Color(0xFF3A0000).withOpacity(0.50);
      canvas.drawRect(Rect.fromLTWH(x, veinY, pxW, spriteH * 0.06), sp);
    }

    if (xFrac.abs() < 0.32) {
      final eyeXFrac = xFrac / 0.32;
      final eyeHalfH = sqrt(1 - eyeXFrac * eyeXFrac) * 0.26 * spriteH;
      final eyeCenterY = sphereTop + spriteH * 0.38;

      sp.color = hp >= 2
          ? Color.fromARGB(255, (255 * (1 - flash * 0.3)).round(), (0xCC * (1 - flash * 0.5)).round(), 0)
          : const Color(0xFFFF6600);
      canvas.drawRect(Rect.fromLTWH(x, eyeCenterY - eyeHalfH, pxW, eyeHalfH * 2), sp);

      if (xFrac.abs() < 0.10) {
        sp.color = const Color(0xFF080000);
        canvas.drawRect(Rect.fromLTWH(x, eyeCenterY - eyeHalfH * 1.1, pxW, eyeHalfH * 2.2), sp);
      }
      if (xFrac.abs() > 0.12 && xFrac.abs() < 0.28) {
        sp.color = const Color(0xFFCC0000).withOpacity(0.70);
        canvas.drawRect(Rect.fromLTWH(x, eyeCenterY - eyeHalfH * 0.25, pxW, eyeHalfH * 0.15), sp);
        canvas.drawRect(Rect.fromLTWH(x, eyeCenterY + eyeHalfH * 0.18, pxW, eyeHalfH * 0.15), sp);
      }
      if (xFrac < -0.06 && xFrac > -0.20) {
        sp.color = Colors.white.withOpacity(0.65);
        canvas.drawRect(Rect.fromLTWH(x, eyeCenterY - eyeHalfH * 0.85, pxW, eyeHalfH * 0.35), sp);
      }
    }

    if (xFrac > 0.28 && xFrac < 0.44) {
      final hornH = spriteH * (0.42 - (xFrac - 0.28) * 1.5);
      sp.color = const Color(0xFF220000);
      canvas.drawRect(Rect.fromLTWH(x, sphereTop - hornH, pxW, hornH), sp);
      sp.color = const Color(0xFF550000);
      canvas.drawRect(Rect.fromLTWH(x, sphereTop - hornH, pxW, hornH * 0.3), sp);
    }
    if (xFrac < -0.28 && xFrac > -0.44) {
      final hornH = spriteH * (0.42 - (-xFrac - 0.28) * 1.5);
      sp.color = const Color(0xFF220000);
      canvas.drawRect(Rect.fromLTWH(x, sphereTop - hornH, pxW, hornH), sp);
      sp.color = const Color(0xFF550000);
      canvas.drawRect(Rect.fromLTWH(x, sphereTop - hornH, pxW, hornH * 0.3), sp);
    }

    if (xFrac.abs() < 0.38) {
      final mawY = sphereTop + spriteH * 0.68;
      final mawH = spriteH * 0.28;
      sp.color = const Color(0xFF0A0000);
      canvas.drawRect(Rect.fromLTWH(x, mawY, pxW, mawH), sp);
      final toothPhase = ((xFrac + 0.38) / 0.76 * 7).floor();
      sp.color = Colors.white.withOpacity(0.88);
      if (toothPhase % 2 == 0) {
        canvas.drawRect(Rect.fromLTWH(x, mawY, pxW, mawH * 0.45), sp);
      } else {
        canvas.drawRect(Rect.fromLTWH(x, mawY, pxW, mawH * 0.25), sp);
      }
      if (toothPhase % 2 == 1) {
        sp.color = Colors.white.withOpacity(0.75);
        canvas.drawRect(Rect.fromLTWH(x, mawY + mawH - mawH * 0.40, pxW, mawH * 0.40), sp);
      }
      sp.color = const Color(0xFF880000).withOpacity(0.60);
      canvas.drawRect(Rect.fromLTWH(x, mawY - 1, pxW, 2), sp);
      canvas.drawRect(Rect.fromLTWH(x, mawY + mawH, pxW, 2), sp);
    }
  }

  void _drawSkeletonColumn(Canvas canvas, Paint sp, int sx, double pxW,
      double by, double sh, double v, double frac, double hp, double flash,
      [double time = 0]) {
    final x = sx * pxW;
    final walkCycle = sin(time * 4.5);
    final bone = Color.fromARGB(255, (0xE8 * (1 - flash) + 255 * flash).round(),
        (0xE4 * (1 - flash) + 255 * flash).round(), (0xCC * (1 - flash)).round());
    const dark = Color(0xFF111111);

    if (frac >= 0.28 && frac <= 0.72) {
      sp.color = bone;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 0.5, pxW, v * 4), sp);
      if ((frac >= 0.32 && frac <= 0.44) || (frac >= 0.56 && frac <= 0.68)) {
        sp.color = dark;
        canvas.drawRect(Rect.fromLTWH(x, by + v * 1.5, pxW, v * 1.8), sp);
      }
      if (frac >= 0.45 && frac <= 0.55) {
        sp.color = dark;
        canvas.drawRect(Rect.fromLTWH(x, by + v * 2.8, pxW, v * 1.2), sp);
      }
      if (frac >= 0.34 && frac <= 0.66) {
        sp.color = bone;
        canvas.drawRect(Rect.fromLTWH(x, by + v * 4.0, pxW, v * 0.5), sp);
        if ((frac + 0.04).round() % 2 == 0) {
          sp.color = dark;
          canvas.drawRect(Rect.fromLTWH(x, by + v * 4.0, pxW, v * 0.5), sp);
        }
      }
    }

    if (frac >= 0.44 && frac <= 0.56) {
      sp.color = bone;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 4.5, pxW, v * 1), sp);
    }

    if (frac >= 0.47 && frac <= 0.53) {
      sp.color = bone;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 5.5, pxW, v * 8.5), sp);
    }

    if (frac >= 0.28 && frac <= 0.72) {
      for (int rib = 0; rib < 5; rib++) {
        sp.color = bone;
        canvas.drawRect(Rect.fromLTWH(x, by + v * (6 + rib * 1.4), pxW, v * 0.6), sp);
      }
    }

    if (frac >= 0.15 && frac <= 0.85) {
      sp.color = bone;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 5.5, pxW, v * 1), sp);
    }

    if ((frac >= 0.12 && frac <= 0.26) || (frac >= 0.74 && frac <= 0.88)) {
      final isLeft = frac <= 0.50;
      final armOff = (isLeft ? -walkCycle : walkCycle) * v * 2.0;
      sp.color = bone;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 6 + armOff, pxW, v * 6), sp);
    }

    if (frac >= 0.28 && frac <= 0.72) {
      sp.color = bone;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 14, pxW, v * 1.5), sp);
    }

    if ((frac >= 0.32 && frac <= 0.46) || (frac >= 0.54 && frac <= 0.68)) {
      final isLeft = frac <= 0.50;
      final legOff = (isLeft ? walkCycle : -walkCycle) * v * 1.8;
      sp.color = bone;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 15.5 + legOff, pxW, v * 4.5), sp);
    }
  }

  void _drawTrollColumn(Canvas canvas, Paint sp, int sx, double pxW,
      double by, double sh, double v, double frac, double hp,
      double flash, double teleportFlash, double time) {
    if (v < 0.01) return;
    final x = sx * pxW;

    final camoBase = 0.22 + flash * 0.60 + teleportFlash * 0.45;
    final camoAlpha = (camoBase.clamp(0.0, 1.0) * 255).round();

    final shimPhase = (frac * 9.0 + time * 2.8) % 1.0;
    final shimA = (12 + (sin(time * 4.5 + frac * 18.0) * 8.0).abs()).round().clamp(5, 28);
    sp.color = shimPhase < 0.5
        ? Color.fromARGB(shimA, 160, 220, 255)
        : Color.fromARGB(shimA, 255, 180, 100);
    canvas.drawRect(Rect.fromLTWH(x, by, pxW, sh), sp);

    final skinR = (0x44 + (255 - 0x44) * flash).round().clamp(0, 255);
    final skinG = (0x6A * (1.0 - flash * 0.6)).round().clamp(0, 255);

    Color s(int r, int g, int b) => Color.fromARGB(camoAlpha, r, g, b);
    Color ss(Color c) => Color.fromARGB(camoAlpha, c.red, c.green, c.blue);

    final skin   = s(skinR, skinG, 0x22);
    final shadow = s(0x1A, 0x2A, 0x08);
    final eyeCol = hp > 6
        ? s((0xFF * (1 - flash * 0.3)).round(), 0, 0)
        : s(255, 255, 255);

    final walkCycle = sin(time * 7.0);

    if (frac >= 0.20 && frac <= 0.80) {
      sp.color = skin;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 0.5, pxW, v * 4.5), sp);
      sp.color = shadow;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 0.5, pxW, v * 0.8), sp);
    }

    if ((frac >= 0.32 && frac <= 0.42) || (frac >= 0.58 && frac <= 0.68)) {
      final eyeAlpha = (camoAlpha * 2.5).round().clamp(0, 255);
      sp.color = Color.fromARGB(eyeAlpha, eyeCol.red, eyeCol.green, eyeCol.blue);
      canvas.drawRect(Rect.fromLTWH(x, by + v * 1.2, pxW, v * 1.3), sp);
      sp.color = Color.fromARGB((eyeAlpha * 0.8).round(), 255, 255, 255);
      canvas.drawRect(Rect.fromLTWH(x, by + v * 1.3, pxW, v * 0.4), sp);
    }

    if (frac >= 0.44 && frac <= 0.56) {
      sp.color = s((skinR * 0.7).round(), (skinG * 0.5).round(), 0);
      canvas.drawRect(Rect.fromLTWH(x, by + v * 2.5, pxW, v * 1.0), sp);
    }

    if ((frac >= 0.30 && frac <= 0.38) || (frac >= 0.62 && frac <= 0.70)) {
      sp.color = ss(const Color(0xFFDDCC88));
      canvas.drawRect(Rect.fromLTWH(x, by + v * 3.8, pxW, v * 1.2), sp);
    }

    if (frac >= 0.08 && frac <= 0.92) {
      sp.color = skin;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 4.0, pxW, v * 10.0), sp);
    }
    if ((frac >= 0.10 && frac <= 0.24) || (frac >= 0.76 && frac <= 0.90)) {
      sp.color = s((skinR * 1.3).clamp(0,255).round(), (skinG * 1.3).clamp(0,255).round(), 0);
      canvas.drawRect(Rect.fromLTWH(x, by + v * 3.5, pxW, v * 4.0), sp);
    }
    if (frac >= 0.35 && frac <= 0.65) {
      for (int f = 0; f < 3; f++) {
        sp.color = f.isEven ? shadow : skin;
        canvas.drawRect(Rect.fromLTWH(x, by + v * (6.5 + f * 2.0), pxW, v * 0.8), sp);
      }
    }

    if ((frac >= 0.00 && frac <= 0.08) || (frac >= 0.92 && frac <= 1.00)) {
      final isLeft = frac <= 0.50;
      final armOff = (isLeft ? -walkCycle : walkCycle) * v * 1.2;
      sp.color = shadow;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 4.0 + armOff, pxW, v * 9.0), sp);
      sp.color = ss(const Color(0xFFCCCC88));
      canvas.drawRect(Rect.fromLTWH(x, by + v * 12.0 + armOff, pxW, v * 1.5), sp);
    }

    if ((frac >= 0.25 && frac <= 0.42) || (frac >= 0.58 && frac <= 0.75)) {
      final isLeft = frac <= 0.50;
      final legOff = (isLeft ? walkCycle : -walkCycle) * v * 1.4;
      sp.color = skin;
      canvas.drawRect(Rect.fromLTWH(x, by + v * 14 + legOff, pxW, v * 6.0), sp);
      sp.color = s((skinR * 1.4).clamp(0,255).round(), (skinG * 1.1).clamp(0,255).round(), 0);
      canvas.drawRect(Rect.fromLTWH(x, by + v * 15.5 + legOff, pxW, v * 1.2), sp);
    }

    if (frac >= 0.44 && frac <= 0.56) {
      sp.color = s(0xAA, 0xBB, 0x44);
      canvas.drawRect(Rect.fromLTWH(x, by + v * 18.0, pxW, v * 5.5), sp);
      sp.color = s(0xFF, 0xEE, 0x00);
      canvas.drawRect(Rect.fromLTWH(x, by + v * 22.5, pxW, v * 2.0), sp);
      sp.color = Color.fromARGB((camoAlpha * 1.5).round().clamp(0, 255), 255, 255, 100);
      canvas.drawRect(Rect.fromLTWH(x, by + v * 23.5, pxW, v * 1.0), sp);
    }
    if ((frac >= 0.38 && frac <= 0.44) || (frac >= 0.56 && frac <= 0.62)) {
      sp.color = s(0x88, 0x99, 0x22);
      canvas.drawRect(Rect.fromLTWH(x, by + v * 19.5, pxW, v * 2.0), sp);
    }

    if (teleportFlash > 0) {
      sp.color = Color.fromARGB((teleportFlash * 120).round(), 0x44, 0xFF, 0xCC);
      canvas.drawRect(Rect.fromLTWH(x, by, pxW, sh), sp);
    }
  }

  void _drawRelic(Canvas canvas, Size size, double pxW, double pxH) {
    final dx = relicX - posX, dy = relicY - posY;
    final invDet = 1.0 / (planeX * dirY - dirX * planeY);
    final transformX = invDet * (dirY * dx - dirX * dy);
    final transformY = invDet * (-planeY * dx + planeX * dy);
    if (transformY <= 0.1) return;

    const numCols = 240;
    final screenCol = (numCols ~/ 2 * (1 + transformX / transformY)).round();
    if (screenCol < 0 || screenCol >= numCols) return;
    if (transformY >= zBuf[screenCol]) return;

    final sx = screenCol * pxW;
    final baseH = (80 / transformY).abs();
    final sprH = (baseH * 0.22).clamp(4.0, 28.0);
    final sy = size.height * 0.5 + baseH * pxH * 0.14;

    final pulse = 0.7 + sin(time * 3.5) * 0.3;
    final sp = Paint()..isAntiAlias = true;

    sp.color = Color.fromARGB((70 * pulse).round(), 0x00, 0xFF, 0x88);
    canvas.drawCircle(Offset(sx, sy), sprH * pxW * 1.6, sp);

    sp.color = Color.fromARGB((140 * pulse).round(), 0x00, 0xFF, 0x66);
    canvas.drawCircle(Offset(sx, sy), sprH * pxW * 0.95, sp);

    sp.color = const Color(0xFF88FFCC);
    canvas.drawCircle(Offset(sx, sy), sprH * pxW * 0.50, sp);

    sp.color = Colors.white;
    canvas.drawCircle(Offset(sx, sy), sprH * pxW * 0.18, sp);
  }

  void _drawScreenFx(Canvas canvas, Size size) {
    if (megaAlive) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFF080004).withOpacity(0.45)..isAntiAlias = false);
      final megaPulse = (0.3 + 0.15 * (time * 1.5 % 1.0)).clamp(0.0, 0.55);
      final vp = Paint()..shader = RadialGradient(
        center: Alignment.center, radius: 0.7,
        colors: [const Color(0x00000000), Color.fromARGB((megaPulse * 200).round(), 0x44, 0x00, 0x22)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vp);
    }
    if (dimFlash > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFF0A0000).withOpacity(dimFlash * 0.82)..isAntiAlias = false);
    }
    if (shootFlash > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.orange.withOpacity(shootFlash * 0.22)..isAntiAlias = false);
    }
    if (hitFlash > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.red.withOpacity(hitFlash * 0.50)..isAntiAlias = false);
      if (hitFlash > 0.65) {
        final sp = Paint()
          ..color = const Color(0xFF770000).withOpacity((hitFlash - 0.65) * 1.5)
          ..isAntiAlias = false;
        canvas.drawRect(Rect.fromLTWH(0, size.height * 0.22, size.width * 0.14, size.height * 0.12), sp);
        canvas.drawRect(Rect.fromLTWH(size.width * 0.82, size.height * 0.30, size.width * 0.14, size.height * 0.10), sp);
        canvas.drawRect(Rect.fromLTWH(size.width * 0.38, 0, size.width * 0.24, size.height * 0.07), sp);
      }
    }
  }

  void _drawHud(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;

    p.color = Colors.black.withOpacity(0.78);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 30), p);

    const barX = 8.0, barY = 8.0, barW = 90.0, barH = 14.0;
    final hFrac = (health / 100.0).clamp(0.0, 1.0);
    final barFill = health > 60
        ? const Color(0xFF22CC44)
        : health > 30 ? const Color(0xFFFF8800) : const Color(0xFFCC1111);

    p.color = const Color(0xFF222222);
    canvas.drawRect(Rect.fromLTWH(barX, barY, barW, barH), p);
    p.color = barFill;
    canvas.drawRect(Rect.fromLTWH(barX, barY, barW * hFrac, barH), p);
    p.color = Colors.white24;
    p.style = PaintingStyle.stroke;
    p.strokeWidth = 1.0;
    canvas.drawRect(Rect.fromLTWH(barX, barY, barW, barH), p);
    p.style = PaintingStyle.fill;

    _hudText(canvas, '❤  $health%', barX + 4, barY + 2, color: Colors.white, size: 10);

    if (relicActive) {
      _hudText(canvas, '✨ ${_pt('RELICARIO', 'RELIC')}', barX + 4, barY + 16,
          color: const Color(0xFF44FF88), size: 7);
    }

    if (megaAlive) {
      _hudText(canvas, '☠ ${_pt('JEFE — RADAR INACTIVO', 'BOSS — RADAR OFFLINE')}', barX + 4, barY + 16,
          color: const Color(0xFFFF00AA), size: 7);
    }

    _hudText(canvas, '💀 $kills', 106, barY + 2, color: Colors.white, size: 10);

    _hudText(canvas, '${_pt('OLA', 'WAVE')} $wave', size.width / 2 - 22, barY + 2,
        color: const Color(0xFFFF8800), size: 10);

    const sel = Color(0xFFFFEE44);
    const dim = Colors.white54;
    double wy = barY;
    _hudText(canvas, '🔫 $ammo', size.width - 78, wy,
        color: weapon == _WeaponType.pistol ? sel : dim, size: 9);
    double pistolY = wy; wy += 9;
    double? shotgunY, smgY;
    if (shotgunUnlocked) {
      _hudText(canvas, '🟠 $shotgunAmmo', size.width - 78, wy,
          color: weapon == _WeaponType.shotgun ? sel : dim, size: 9);
      shotgunY = wy; wy += 9;
    }
    if (smgUnlocked) {
      _hudText(canvas, '⚡ $smgAmmo', size.width - 78, wy,
          color: weapon == _WeaponType.smg ? sel : dim, size: 9);
      smgY = wy;
    }
    final activeY = weapon == _WeaponType.pistol ? pistolY
        : weapon == _WeaponType.shotgun ? (shotgunY ?? pistolY)
        : (smgY ?? pistolY);
    p.color = sel;
    canvas.drawRect(Rect.fromLTWH(size.width - 82, activeY + 1, 2, 7), p);
  }

  void _hudText(Canvas canvas, String text, double x, double y,
      {Color color = Colors.white, double size = 10}) {
    final tp = TextPainter(
      text: TextSpan(text: text,
          style: TextStyle(color: color, fontSize: size,
              fontFamily: 'monospace', fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x, y));
    tp.dispose();
  }

  void _drawCrosshair(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final p = Paint()..color = Colors.white..isAntiAlias = false;
    canvas.drawRect(Rect.fromLTWH(cx - 1, cy - 5, 2, 10), p);
    canvas.drawRect(Rect.fromLTWH(cx - 5, cy - 1, 10, 2), p);
    final gap = Paint()..color = Colors.black..isAntiAlias = false;
    canvas.drawRect(Rect.fromLTWH(cx - 1, cy - 1, 2, 2), gap);
  }

  void _drawRadar(Canvas canvas, Size size) {
    const radarR = 44.0;
    const cx = 55.0;
    final cy = size.height - 62.0;
    const scale = radarR / 7.0;

    final p = Paint()..isAntiAlias = true;

    canvas.save();
    canvas.clipPath(Path()..addOval(
        Rect.fromCircle(center: Offset(cx, cy), radius: radarR)));

    p.color = Colors.black.withOpacity(0.72);
    canvas.drawCircle(Offset(cx, cy), radarR, p);

    final fovHalf = atan(0.66);
    final playerAngle = atan2(-dirY, dirX);
    final conePath = Path()..moveTo(cx, cy);
    const steps = 12;
    for (int i = 0; i <= steps; i++) {
      final a = (playerAngle - fovHalf) + (fovHalf * 2) * i / steps;
      conePath.lineTo(cx + cos(a) * radarR, cy - sin(a) * radarR);
    }
    conePath.close();
    p.color = const Color(0xFFFF6600).withOpacity(0.20);
    canvas.drawPath(conePath, p);

    p.color = const Color(0xFFFF8800).withOpacity(0.70);
    p.style = PaintingStyle.stroke;
    p.strokeWidth = 1.0;
    canvas.drawLine(Offset(cx, cy),
        Offset(cx + cos(playerAngle - fovHalf) * radarR,
               cy - sin(playerAngle - fovHalf) * radarR), p);
    canvas.drawLine(Offset(cx, cy),
        Offset(cx + cos(playerAngle + fovHalf) * radarR,
               cy - sin(playerAngle + fovHalf) * radarR), p);
    p.style = PaintingStyle.fill;

    for (final e in enemies) {
      if (!e.alive) continue;
      final dx = e.x - posX, dy = e.y - posY;
      final rx = cx + dx * scale;
      final ry = cy + dy * scale;
      if ((rx - cx) * (rx - cx) + (ry - cy) * (ry - cy) > (radarR - 3) * (radarR - 3)) continue;

      if (e.type == _EnemyType.troll) {
        continue;
      } else if (e.isMega) {
        p.color = const Color(0xFF8800FF);
        final megaPath = Path()
          ..moveTo(rx, ry - 7)
          ..lineTo(rx + 5, ry)
          ..lineTo(rx, ry + 5)
          ..lineTo(rx - 5, ry)
          ..close();
        canvas.drawPath(megaPath, p);
        p.color = const Color(0xFF00FFAA);
        canvas.drawRect(Rect.fromLTWH(rx - 4.5, ry - 10, 2, 3.5), p);
        canvas.drawRect(Rect.fromLTWH(rx - 1,   ry - 11, 2, 4.0), p);
        canvas.drawRect(Rect.fromLTWH(rx + 2.5, ry - 10, 2, 3.5), p);
        p.color = const Color(0xFFFF00FF);
        p.style = PaintingStyle.stroke;
        p.strokeWidth = 1.2;
        canvas.drawPath(megaPath, p);
        p.style = PaintingStyle.fill;
        _hudText(canvas, '☠', rx - 4, ry - 6.5, color: const Color(0xFFFF00FF), size: 7);
      } else if (e.type == _EnemyType.skeleton) {
        p.color = Colors.white70;
        canvas.drawCircle(Offset(rx, ry), 3.5, p);
        p.color = Colors.black;
        canvas.drawRect(Rect.fromLTWH(rx - 2, ry - 1, 1.5, 1.5), p);
        canvas.drawRect(Rect.fromLTWH(rx + 0.5, ry - 1, 1.5, 1.5), p);
        canvas.drawRect(Rect.fromLTWH(rx - 1, ry + 0.8, 2, 1), p);
      } else if (e.type == _EnemyType.demon) {
        p.color = const Color(0xFFFF3322);
        final path = Path()
          ..moveTo(rx, ry - 4)
          ..lineTo(rx + 3, ry)
          ..lineTo(rx, ry + 3)
          ..lineTo(rx - 3, ry)
          ..close();
        canvas.drawPath(path, p);
        p.color = const Color(0xFFAA1100);
        canvas.drawRect(Rect.fromLTWH(rx - 3.5, ry - 6, 1.5, 2.5), p);
        canvas.drawRect(Rect.fromLTWH(rx + 2, ry - 6, 1.5, 2.5), p);
      } else {
        p.color = const Color(0xFF44BBFF);
        canvas.drawCircle(Offset(rx, ry + 0.5), 3.5, p);
        final hornPath = Path()
          ..moveTo(rx - 1.5, ry - 3)
          ..lineTo(rx, ry - 6)
          ..lineTo(rx + 1.5, ry - 3)
          ..close();
        canvas.drawPath(hornPath, p);
        p.color = Colors.black38;
        p.style = PaintingStyle.stroke;
        p.strokeWidth = 0.8;
        canvas.drawCircle(Offset(rx, ry + 0.5), 3.5, p);
        p.style = PaintingStyle.fill;
      }
    }

    p.color = const Color(0xFF44FF88);
    canvas.drawCircle(Offset(cx, cy), 4.0, p);
    p.style = PaintingStyle.stroke;
    p.strokeWidth = 1.5;
    canvas.drawLine(Offset(cx, cy),
        Offset(cx + dirX * 10, cy + dirY * 10), p);
    p.style = PaintingStyle.fill;

    canvas.restore();

    p.color = const Color(0xFF884400);
    p.style = PaintingStyle.stroke;
    p.strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy), radarR, p);
    p.style = PaintingStyle.fill;

    _hudText(canvas, _pt('RADAR', 'RADAR'), cx - 14, cy + radarR + 3,
        color: const Color(0xFFBB6622), size: 8);
  }

  void _drawWeapon(Canvas canvas, Size size, bool firing) {
    if (weapon == _WeaponType.shotgun) {
      _drawShotgun(canvas, size, firing);
    } else if (weapon == _WeaponType.smg) {
      _drawSmg(canvas, size, firing);
    } else {
      _drawPistol(canvas, size, firing);
    }
  }

  void _drawShotgun(Canvas canvas, Size size, bool firing) {
    canvas.save();
    canvas.translate(size.width * 0.68, size.height * 0.95);
    canvas.rotate(-0.245);

    final p = Paint()..isAntiAlias = false;

    if (firing) {
      p.isAntiAlias = true;
      for (final bx in [-11.0, 11.0]) {
        const by = -113.0;
        p.color = const Color(0xFFFF4400).withOpacity(0.80);
        canvas.drawPath(Path()
          ..moveTo(bx,      by - 32)
          ..lineTo(bx + 9,  by - 4)
          ..lineTo(bx + 15, by + 4)
          ..lineTo(bx + 6,  by - 1)
          ..lineTo(bx,      by + 4)
          ..lineTo(bx - 6,  by - 1)
          ..lineTo(bx - 15, by + 4)
          ..lineTo(bx - 9,  by - 4)
          ..close(), p);
        p.color = const Color(0xFFFFCC00);
        canvas.drawPath(Path()
          ..moveTo(bx,     by - 20)
          ..lineTo(bx + 6, by - 2)
          ..lineTo(bx,     by + 2)
          ..lineTo(bx - 6, by - 2)
          ..close(), p);
        p.color = Colors.white;
        canvas.drawCircle(Offset(bx, by - 4), 3.5, p);
      }
      p.isAntiAlias = false;
    }

    p.color = const Color(0xFF888888);
    canvas.drawRect(const Rect.fromLTWH(-24, -108, 2, 62), p);
    p.color = const Color(0xFF606060);
    canvas.drawRect(const Rect.fromLTWH(-22, -108, 18, 62), p);
    p.color = const Color(0xFF404040);
    canvas.drawRect(const Rect.fromLTWH(-4, -108, 2, 62), p);
    p.color = const Color(0xFF111111);
    canvas.drawRect(const Rect.fromLTWH(-20, -109, 14, 8), p);
    p.color = const Color(0xFF555555);
    canvas.drawRect(const Rect.fromLTWH(-24, -111, 22, 3), p);

    p.color = const Color(0xFF888888);
    canvas.drawRect(const Rect.fromLTWH(2, -108, 2, 62), p);
    p.color = const Color(0xFF606060);
    canvas.drawRect(const Rect.fromLTWH(4, -108, 18, 62), p);
    p.color = const Color(0xFF404040);
    canvas.drawRect(const Rect.fromLTWH(22, -108, 2, 62), p);
    p.color = const Color(0xFF111111);
    canvas.drawRect(const Rect.fromLTWH(6, -109, 14, 8), p);
    p.color = const Color(0xFF555555);
    canvas.drawRect(const Rect.fromLTWH(2, -111, 22, 3), p);

    p.color = const Color(0xFF777777);
    canvas.drawRect(const Rect.fromLTWH(-2, -108, 4, 62), p);

    p.color = const Color(0xFF555555);
    canvas.drawRect(const Rect.fromLTWH(-24, -64, 48, 8), p);
    p.color = const Color(0xFF777777);
    canvas.drawRect(const Rect.fromLTWH(-24, -64, 48, 2), p);

    p.color = const Color(0xFF6B4520);
    canvas.drawRect(const Rect.fromLTWH(-20, -56, 40, 30), p);
    p.color = const Color(0xFF7A5028);
    for (int i = 0; i < 4; i++) {
      canvas.drawRect(Rect.fromLTWH(-18.0 + i * 9, -54, 6, 26), p);
    }

    p.color = const Color(0xFF404040);
    canvas.drawRect(const Rect.fromLTWH(-22, -26, 44, 36), p);
    p.color = const Color(0xFF555555);
    canvas.drawRect(const Rect.fromLTWH(-22, -26, 44, 3), p);
    p.color = const Color(0xFF333333);
    canvas.drawRect(const Rect.fromLTWH(-22, 8,  44, 2), p);
    p.color = const Color(0xFF1A1A1A);
    canvas.drawRect(const Rect.fromLTWH(10, -22, 8, 20), p);

    p.color = const Color(0xFF444444);
    canvas.drawRect(const Rect.fromLTWH(-18, 8,  36, 3), p);
    canvas.drawRect(const Rect.fromLTWH(-18, 8,  3, 22), p);
    canvas.drawRect(const Rect.fromLTWH(15,  8,  3, 22), p);
    canvas.drawRect(const Rect.fromLTWH(-18, 28, 36, 3), p);
    p.color = const Color(0xFF888888);
    canvas.drawRect(const Rect.fromLTWH(-5, 11, 7, 14), p);

    p.color = const Color(0xFF5C3A12);
    canvas.drawRect(const Rect.fromLTWH(-12, 30, 32, 44), p);
    p.color = const Color(0xFF6A4418);
    for (int r = 0; r < 5; r++) {
      canvas.drawRect(Rect.fromLTWH(-9.0, 34.0 + r * 7, 24, 4), p);
    }
    p.color = const Color(0xFF3A2208);
    canvas.drawRect(const Rect.fromLTWH(-12, 72, 32, 4), p);

    canvas.restore();

    if (shotgunAmmo == 0) {
      final tp = TextPainter(
        text: TextSpan(text: _pt('— SIN CARTUCHOS —', '— NO SHELLS —'),
            style: const TextStyle(color: Colors.orange, fontSize: 10,
                fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, size.height * 0.60));
      tp.dispose();
    }
  }

  void _drawPistol(Canvas canvas, Size size, bool firing) {
    canvas.save();
    canvas.translate(size.width * 0.82, size.height * 0.95);
    canvas.rotate(-0.375);

    final p = Paint()..isAntiAlias = false;

    if (firing) {
      p.isAntiAlias = true;
      const cx = 1.0, cy = -103.0;
      p.color = const Color(0xFFFF5500).withOpacity(0.85);
      canvas.drawPath(Path()
        ..moveTo(cx,      cy - 38)
        ..lineTo(cx + 11, cy - 4)
        ..lineTo(cx + 18, cy + 5)
        ..lineTo(cx + 8,  cy - 1)
        ..lineTo(cx,      cy + 5)
        ..lineTo(cx - 8,  cy - 1)
        ..lineTo(cx - 18, cy + 5)
        ..lineTo(cx - 11, cy - 4)
        ..close(), p);
      p.color = const Color(0xFFFFCC00);
      canvas.drawPath(Path()
        ..moveTo(cx,     cy - 25)
        ..lineTo(cx + 8, cy - 3)
        ..lineTo(cx,     cy + 3)
        ..lineTo(cx - 8, cy - 3)
        ..close(), p);
      p.color = Colors.white;
      canvas.drawCircle(Offset(cx, cy - 6), 5, p);
      p.isAntiAlias = false;
    }

    p.color = const Color(0xFF888888);
    canvas.drawRect(const Rect.fromLTWH(-7, -98, 2, 52), p);
    p.color = const Color(0xFF606060);
    canvas.drawRect(const Rect.fromLTWH(-5, -98, 14, 52), p);
    p.color = const Color(0xFF404040);
    canvas.drawRect(const Rect.fromLTWH(9, -98, 3, 52), p);
    p.color = const Color(0xFF111111);
    canvas.drawRect(const Rect.fromLTWH(-3, -99, 8, 6), p);
    p.color = const Color(0xFF666666);
    canvas.drawRect(const Rect.fromLTWH(-9, -102, 24, 4), p);
    p.color = Colors.white.withOpacity(0.30);
    canvas.drawRect(const Rect.fromLTWH(-2, -99, 8, 2), p);

    p.color = const Color(0xFF333333);
    canvas.drawRect(const Rect.fromLTWH(-15, -86, 32, 82), p);
    p.color = const Color(0xFF555555);
    canvas.drawRect(const Rect.fromLTWH(-15, -86, 3, 82), p);
    p.color = const Color(0xFF484848);
    canvas.drawRect(const Rect.fromLTWH(-15, -86, 32, 3), p);
    p.color = const Color(0xFF282828);
    for (int i = 0; i < 7; i++) {
      canvas.drawRect(Rect.fromLTWH(-13, -34.0 + i * 5, 28, 2), p);
    }
    p.color = const Color(0xFF555555);
    canvas.drawRect(const Rect.fromLTWH(-14, -90, 7, 5), p);
    canvas.drawRect(const Rect.fromLTWH(7,  -90, 7, 5), p);
    p.color = const Color(0xFF111111);
    canvas.drawRect(const Rect.fromLTWH(-6, -90, 13, 5), p);
    p.color = const Color(0xFF1A1A1A);
    canvas.drawRect(const Rect.fromLTWH(11, -70, 5, 22), p);
    p.color = const Color(0xFFB8860B);
    canvas.drawRect(const Rect.fromLTWH(12, -67, 3, 15), p);

    p.color = const Color(0xFF2E2E2E);
    canvas.drawRect(const Rect.fromLTWH(-17, -6, 34, 24), p);
    p.color = const Color(0xFF444444);
    canvas.drawRect(const Rect.fromLTWH(-17, -6, 3, 24), p);
    p.color = const Color(0xFF262626);
    canvas.drawRect(const Rect.fromLTWH(-17, 14, 34, 4), p);

    p.color = const Color(0xFF303030);
    canvas.drawRect(const Rect.fromLTWH(-14, 16, 28, 3), p);
    canvas.drawRect(const Rect.fromLTWH(-14, 16, 3, 20), p);
    canvas.drawRect(const Rect.fromLTWH(11,  16, 3, 20), p);
    canvas.drawRect(const Rect.fromLTWH(-14, 33, 28, 3), p);
    p.color = const Color(0xFF888888);
    canvas.drawRect(const Rect.fromLTWH(-4, 19, 7, 12), p);

    p.color = const Color(0xFF222222);
    canvas.drawRect(const Rect.fromLTWH(-15, 25, 34, 46), p);
    p.color = const Color(0xFF333333);
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 4; c++) {
        canvas.drawRect(Rect.fromLTWH(-11.0 + c*7, 29.0 + r*7, 4, 3), p);
      }
    }
    p.color = const Color(0xFF1A1A1A);
    canvas.drawRect(const Rect.fromLTWH(-15, 69, 34, 5), p);
    p.color = const Color(0xFF404040);
    canvas.drawRect(const Rect.fromLTWH(-13, 73, 30, 4), p);

    p.color = const Color(0xFF777777);
    canvas.drawRect(const Rect.fromLTWH(13, -18, 10, 11), p);
    p.color = const Color(0xFF444444);
    canvas.drawRect(const Rect.fromLTWH(15, -16, 6, 8), p);

    canvas.restore();

    if (ammo == 0) {
      final tp = TextPainter(
        text: TextSpan(text: _pt('— SIN BALAS —', '— NO AMMO —'),
          style: const TextStyle(color: Colors.red, fontSize: 10,
            fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, size.height * 0.60));
      tp.dispose();
    }
  }

  void _drawSmg(Canvas canvas, Size size, bool firing) {
    canvas.save();
    canvas.translate(size.width * 0.78, size.height * 0.95);
    canvas.rotate(-0.325);

    final p = Paint()..isAntiAlias = false;

    if (firing) {
      p.isAntiAlias = true;
      const cx = 0.0, cy = -78.0;
      p.color = const Color(0xFFFF6600).withOpacity(0.80);
      canvas.drawPath(Path()
        ..moveTo(cx,      cy - 26)
        ..lineTo(cx + 9,  cy - 3)
        ..lineTo(cx + 14, cy + 3)
        ..lineTo(cx + 6,  cy)
        ..lineTo(cx,      cy + 3)
        ..lineTo(cx - 6,  cy)
        ..lineTo(cx - 14, cy + 3)
        ..lineTo(cx - 9,  cy - 3)
        ..close(), p);
      p.color = const Color(0xFFFFCC00);
      canvas.drawPath(Path()
        ..moveTo(cx, cy - 17)
        ..lineTo(cx + 6, cy - 2)
        ..lineTo(cx, cy + 2)
        ..lineTo(cx - 6, cy - 2)
        ..close(), p);
      p.color = Colors.white;
      canvas.drawCircle(Offset(cx, cy - 4), 3.5, p);
      p.isAntiAlias = false;
    }

    p.color = const Color(0xFF888888);
    canvas.drawRect(const Rect.fromLTWH(-4, -72, 2, 36), p);
    p.color = const Color(0xFF666666);
    canvas.drawRect(const Rect.fromLTWH(-2, -72, 10, 36), p);
    p.color = const Color(0xFF404040);
    canvas.drawRect(const Rect.fromLTWH(8, -72, 2, 36), p);
    p.color = const Color(0xFF111111);
    canvas.drawRect(const Rect.fromLTWH(-1, -73, 6, 5), p);
    p.color = const Color(0xFF555555);
    canvas.drawRect(const Rect.fromLTWH(-6, -72, 16, 4), p);
    p.color = const Color(0xFF444444);
    canvas.drawRect(const Rect.fromLTWH(-6, -68, 16, 28), p);
    p.color = const Color(0xFF222222);
    for (int i = 0; i < 3; i++) {
      canvas.drawRect(Rect.fromLTWH(-4, -64.0 + i * 7, 12, 3), p);
    }

    p.color = const Color(0xFF383838);
    canvas.drawRect(const Rect.fromLTWH(-10, -40, 28, 32), p);
    p.color = const Color(0xFF4A4A4A);
    canvas.drawRect(const Rect.fromLTWH(-10, -40, 28, 3), p);
    p.color = const Color(0xFF282828);
    canvas.drawRect(const Rect.fromLTWH(-10, -10, 28, 2), p);
    p.color = const Color(0xFF555555);
    canvas.drawRect(const Rect.fromLTWH(16, -34, 5, 6), p);
    p.color = const Color(0xFF1A1A1A);
    canvas.drawRect(const Rect.fromLTWH(12, -32, 5, 16), p);

    p.color = const Color(0xFF2A2A2A);
    canvas.drawRect(const Rect.fromLTWH(-10, -8, 6, 30), p);
    p.color = const Color(0xFF444444);
    canvas.drawRect(const Rect.fromLTWH(-10, -8, 2, 30), p);

    p.color = const Color(0xFF2E2E2E);
    canvas.drawRect(const Rect.fromLTWH(-4, -8, 14, 38), p);
    p.color = const Color(0xFF444444);
    canvas.drawRect(const Rect.fromLTWH(-4, -8, 3, 38), p);
    p.color = const Color(0xFF1A1A1A);
    canvas.drawRect(const Rect.fromLTWH(-4, 28, 14, 4), p);
    p.color = const Color(0xFF383838);
    for (int i = 0; i < 3; i++) {
      canvas.drawRect(Rect.fromLTWH(-2, -4.0 + i * 9, 10, 2), p);
    }

    p.color = const Color(0xFF333333);
    canvas.drawRect(const Rect.fromLTWH(-8, -8, 22, 2), p);
    canvas.drawRect(const Rect.fromLTWH(-8, -8, 2, 16), p);
    canvas.drawRect(const Rect.fromLTWH(12, -8, 2, 16), p);
    canvas.drawRect(const Rect.fromLTWH(-8, 6, 22, 2), p);
    p.color = const Color(0xFF888888);
    canvas.drawRect(const Rect.fromLTWH(-1, -5, 5, 10), p);

    canvas.restore();

    if (smgAmmo == 0) {
      final tp = TextPainter(
        text: TextSpan(text: _pt('— SIN MUNICIÓN —', '— NO ROUNDS —'),
          style: const TextStyle(color: Colors.orange, fontSize: 10,
            fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, size.height * 0.60));
      tp.dispose();
    }
  }
}
