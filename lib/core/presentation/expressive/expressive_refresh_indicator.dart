import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:mygalia/core/presentation/expressive/loading_indicator.dart';

/// « Tirer pour actualiser » Material 3 Expressive.
///
/// Pendant le geste, un disque descend du haut de la liste : son cercle
/// devient un éclat en tournant au fil de la traction. Relâché assez bas,
/// il reste en place et ses formes se transforment pendant tout le
/// rafraîchissement ([onRefresh]), puis il disparaît.
///
/// Le même indicateur apparaît quand un rafraîchissement est lancé
/// ailleurs (bouton, retour au premier plan, retour du réseau) : il suit
/// [refreshing].
///
/// Mécanique du geste reprise du RefreshIndicator de Flutter (mêmes
/// seuils, même gestion des notifications de défilement).
class ExpressiveRefreshIndicator extends StatefulWidget {
  const ExpressiveRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.refreshing = false,
    this.displacement = 24,
    this.edgeOffset = 0,
    this.notificationPredicate = defaultScrollNotificationPredicate,
    this.semanticsLabel = 'Actualisation',
  });

  final RefreshCallback onRefresh;
  final Widget child;

  /// Un rafraîchissement est en cours (lancé ou non par le geste).
  final bool refreshing;

  /// Distance du haut de la liste à l'indicateur en place.
  final double displacement;

  /// Décalage du haut de la zone de l'indicateur.
  final double edgeOffset;

  final ScrollNotificationPredicate notificationPredicate;
  final String semanticsLabel;

  /// Diamètre du disque (Material 3 Expressive).
  static const double indicatorSize = 48;

  @override
  State<ExpressiveRefreshIndicator> createState() => _ExpressiveRefreshIndicatorState();
}

enum _Status { drag, armed, snap, refresh, done, canceled }

class _ExpressiveRefreshIndicatorState extends State<ExpressiveRefreshIndicator>
    with TickerProviderStateMixin {
  // Traction qui amène l'indicateur à son maximum, en part de la hauteur
  // visible ; dépassement possible au-delà de la position de repos.
  static const double _dragContainerExtentPercentage = 0.25;
  static const double _dragSizeFactorLimit = 1.5;
  static const Duration _snapDuration = Duration(milliseconds: 150);
  static const Duration _appearDuration = Duration(milliseconds: 260);
  static const Duration _scaleDuration = Duration(milliseconds: 200);

  // Créés dans initState, jamais à la destruction (cf. dispose).
  late final AnimationController _positionController;
  late final AnimationController _scaleController;
  late final Animation<double> _positionFactor;
  late final Animation<double> _scaleFactor;

  _Status? _status;
  double? _dragOffset;

  /// Affichage commandé par [ExpressiveRefreshIndicator.refreshing] plutôt
  /// que par le geste.
  bool _external = false;

  @override
  void initState() {
    super.initState();
    _positionController = AnimationController(vsync: this);
    _scaleController = AnimationController(vsync: this);
    _positionFactor = _positionController.drive(Tween<double>(begin: 0, end: _dragSizeFactorLimit));
    _scaleFactor = _scaleController.drive(Tween<double>(begin: 1, end: 0));
    if (widget.refreshing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.refreshing && _status == null) _showExternal();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ExpressiveRefreshIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshing && !oldWidget.refreshing && _status == null) {
      _showExternal();
    } else if (!widget.refreshing && _external && _status == _Status.refresh) {
      _dismiss(_Status.done);
    }
  }

  @override
  void dispose() {
    _positionController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  bool _shouldStart(ScrollNotification notification) =>
      notification is ScrollStartNotification &&
      notification.dragDetails != null &&
      notification.metrics.axisDirection == AxisDirection.down &&
      notification.metrics.extentBefore == 0 &&
      _status == null &&
      _start();

  bool _start() {
    _dragOffset = 0;
    _scaleController.value = 0;
    _positionController.value = 0;
    return true;
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.notificationPredicate(notification)) return false;
    if (_shouldStart(notification)) {
      setState(() => _status = _Status.drag);
      return false;
    }
    final bool dragging = _status == _Status.drag || _status == _Status.armed;
    if (notification.metrics.axisDirection != AxisDirection.down) {
      if (dragging) _dismiss(_Status.canceled);
    } else if (notification is ScrollUpdateNotification) {
      if (dragging) {
        _dragOffset = _dragOffset! - notification.scrollDelta!;
        _checkDragOffset(notification.metrics.viewportDimension);
      }
      // Rebond (iOS) : le défilement n'est plus guidé par le doigt.
      if (_status == _Status.armed && notification.dragDetails == null) _show();
    } else if (notification is OverscrollNotification) {
      if (dragging) {
        _dragOffset = _dragOffset! - notification.overscroll;
        _checkDragOffset(notification.metrics.viewportDimension);
      }
    } else if (notification is ScrollEndNotification) {
      switch (_status) {
        case _Status.armed:
          if (_positionController.value < 1) {
            _dismiss(_Status.canceled);
          } else {
            _show();
          }
        case _Status.drag:
          _dismiss(_Status.canceled);
        case _Status.snap || _Status.refresh || _Status.done || _Status.canceled || null:
          break;
      }
    }
    return false;
  }

  bool _handleIndicatorNotification(OverscrollIndicatorNotification notification) {
    if (notification.depth != 0 || !notification.leading) return false;
    if (_status == _Status.drag) {
      notification.disallowIndicator();
      return true;
    }
    return false;
  }

  void _checkDragOffset(double containerExtent) {
    double value = _dragOffset! / (containerExtent * _dragContainerExtentPercentage);
    if (_status == _Status.armed) value = math.max(value, 1 / _dragSizeFactorLimit);
    _positionController.value = value.clamp(0, 1);
    if (_status == _Status.drag && _positionController.value >= 1 / _dragSizeFactorLimit) {
      _status = _Status.armed;
    }
  }

  /// Relâché assez bas : l'indicateur se cale et le rafraîchissement part.
  void _show() {
    _status = _Status.snap;
    _external = false;
    _positionController.animateTo(1 / _dragSizeFactorLimit, duration: _snapDuration).then((void _) {
      if (!mounted || _status != _Status.snap) return;
      setState(() => _status = _Status.refresh);
      widget.onRefresh().whenComplete(() {
        if (!mounted || _status != _Status.refresh) return;
        if (widget.refreshing) {
          // Encore en cours ailleurs : l'indicateur suit désormais l'état.
          _external = true;
        } else {
          _dismiss(_Status.done);
        }
      });
    });
  }

  /// Rafraîchissement lancé hors du geste : l'indicateur descend et tourne.
  void _showExternal() {
    _start();
    _external = true;
    setState(() => _status = _Status.snap);
    _positionController
        .animateTo(1 / _dragSizeFactorLimit, duration: _appearDuration, curve: Curves.easeOutCubic)
        .then((void _) {
      if (!mounted || _status != _Status.snap) return;
      setState(() => _status = _Status.refresh);
      if (!widget.refreshing) _dismiss(_Status.done);
    });
  }

  Future<void> _dismiss(_Status newStatus) async {
    // Hors de la notification en cours de traitement.
    await Future<void>.value();
    if (!mounted) return;
    setState(() => _status = newStatus);
    if (newStatus == _Status.done) {
      await _scaleController.animateTo(1, duration: _scaleDuration, curve: Curves.easeInCubic);
    } else {
      await _positionController.animateTo(0, duration: _scaleDuration);
    }
    if (!mounted || _status != newStatus) return;
    _dragOffset = null;
    _external = false;
    setState(() => _status = null);
    // Un nouveau rafraîchissement a pu commencer entre-temps.
    if (widget.refreshing) _showExternal();
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: NotificationListener<OverscrollIndicatorNotification>(
        onNotification: _handleIndicatorNotification,
        child: widget.child,
      ),
    );
    final _Status? status = _status;
    final bool indeterminate = status == _Status.refresh ||
        status == _Status.done ||
        (status == _Status.snap && _external);
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        child,
        if (status != null)
          Positioned(
            top: widget.edgeOffset,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: SizeTransition(
                alignment: const AlignmentDirectional(-1, 1),
                sizeFactor: _positionFactor,
                child: Padding(
                  padding: EdgeInsets.only(top: widget.displacement),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ScaleTransition(
                      scale: _scaleFactor,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: dark ? 0.4 : 0.14),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: AnimatedBuilder(
                          animation: _positionController,
                          builder: (BuildContext context, Widget? _) => ExpressiveLoadingIndicator(
                            size: ExpressiveRefreshIndicator.indicatorSize,
                            contained: true,
                            progress: indeterminate ? null : _positionFactor.value,
                            // Enchaîne sans à-coup la forme du geste et
                            // l'animation continue.
                            rotationOffset: indeterminate
                                ? ExpressiveLoadingIndicator.rotationAtFull - math.pi / 2
                                : 0,
                            semanticsLabel: widget.semanticsLabel,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
