import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';

/// `BlocBuilder`, который перестраивается не чаще заданного интервала.
///
/// [RtEegDataBloc] делает `emit` **на каждый отсчёт** — 250 раз в секунду на
/// устройство. Пока на экране одна вкладка, это терпимо; в мозаике на десять
/// устройств это 2500 перестроек в секунду и десяток перерисовок графиков за
/// кадр. Мелкой панели столько не нужно: на 380 пикселях разницы между 10 и 250
/// кадрами в секунду не видно.
///
/// Ограничивается **только перерисовка**. Данные копятся как раньше: буферы,
/// фильтр, FFT и ритмы считаются на каждый отсчёт. Это принципиально — попытка
/// проредить сами данные уже ломала картинку (провал на батчинге), поэтому
/// пайплайн не трогаем вообще.
///
/// Таймера внутри нет намеренно: перестройку двигает приходящий поток, а не
/// собственные часы. Живой таймер в виджете ронял бы виджет-тесты на pending
/// timer, а если данные прекратились, то и перерисовывать нечего — панель и
/// должна замереть на последнем кадре.
/// Темп перерисовки живых графиков — и во вкладке, и в мозаике.
///
/// 16 мс это чуть чаще кадра при 60 Гц: ограничитель срезает лишние перестройки
/// (их прилетает 250 в секунду на устройство), но ни одного кадра не
/// пропускает. Больше кадра всё равно не нарисовать — несколько `setState`
/// внутри одного кадра схлопываются в одну перестройку, так что перестройки
/// сверх этого были чистой тратой.
const livePlotRefreshInterval = Duration(milliseconds: 16);

class ThrottledBlocBuilder<B extends StateStreamable<S>, S>
    extends StatefulWidget {
  const ThrottledBlocBuilder({
    super.key,
    required this.bloc,
    required this.interval,
    required this.builder,
  });

  final B bloc;

  /// Минимальный промежуток между перестройками.
  final Duration interval;

  final Widget Function(BuildContext context, S state) builder;

  @override
  State<ThrottledBlocBuilder<B, S>> createState() =>
      _ThrottledBlocBuilderState<B, S>();
}

class _ThrottledBlocBuilderState<B extends StateStreamable<S>, S>
    extends State<ThrottledBlocBuilder<B, S>> {
  late StreamSubscription<S> _subscription;
  late S _state;
  final Stopwatch _sinceLastBuild = Stopwatch();

  @override
  void initState() {
    super.initState();
    _state = widget.bloc.state;
    _sinceLastBuild.start();
    _subscription = widget.bloc.stream.listen(_onState);
  }

  @override
  void didUpdateWidget(ThrottledBlocBuilder<B, S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bloc, widget.bloc)) {
      _subscription.cancel();
      _state = widget.bloc.state;
      _subscription = widget.bloc.stream.listen(_onState);
    }
  }

  void _onState(S state) {
    if (_sinceLastBuild.elapsed < widget.interval) return;
    _sinceLastBuild.reset();
    setState(() => _state = state);
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _state);
}
