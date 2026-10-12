import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Une destination de la barre de navigation.
@immutable
class PillNavItem {
  const PillNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Barre de navigation flottante en pilule.
///
/// L'onglet sélectionné s'élargit en pilule colorée et affiche son titre ;
/// les autres n'affichent que leur icône (le titre reste annoncé aux
/// lecteurs d'écran et en info-bulle). Largeur, couleur, icône et titre
/// sont animés au changement d'onglet.
class FloatingPillNavBar extends StatelessWidget {
  const FloatingPillNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  static const Duration duration = Duration(milliseconds: 380);
  static const Curve curve = Curves.easeOutCubic;

  final List<PillNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        // Ombre portée floutée explicite : douce et identique partout (le
        // rendu de `elevation` varie selon le moteur de rendu).
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: dark ? scheme.surfaceContainerHigh : scheme.surface,
            shape: StadiumBorder(
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: dark ? 0.45 : 0.25),
              ),
            ),
            shadows: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.35 : 0.10),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                // Place laissée au titre une fois les autres onglets (icône
                // seule) et la pilule servis : jamais de débordement, même
                // sur un petit écran ou avec une grande taille de texte.
                final double maxLabelWidth = (constraints.maxWidth -
                        (items.length - 1) * _PillNavButton.collapsedWidth -
                        _PillNavButton.expandedChromeWidth)
                    .clamp(0, 140)
                    .toDouble();
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (int i = 0; i < items.length; i++)
                      _PillNavButton(
                        item: items[i],
                        selected: i == selectedIndex,
                        maxLabelWidth: maxLabelWidth,
                        onTap: () {
                          if (i == selectedIndex) return;
                          HapticFeedback.selectionClick();
                          onSelected(i);
                        },
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PillNavButton extends StatelessWidget {
  const _PillNavButton({
    required this.item,
    required this.selected,
    required this.maxLabelWidth,
    required this.onTap,
  });

  static const double _iconSize = 24;
  static const double _collapsedPadding = 14;
  static const double _expandedPadding = 16;
  static const double _labelGap = 8;

  /// Largeur d'un onglet replié (icône seule).
  static const double collapsedWidth = _iconSize + 2 * _collapsedPadding;

  /// Largeur d'un onglet déplié, hors titre.
  static const double expandedChromeWidth = _iconSize + _labelGap + 2 * _expandedPadding;

  final PillNavItem item;
  final bool selected;
  final double maxLabelWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color foreground =
        selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    const StadiumBorder shape = StadiumBorder();

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: Tooltip(
        message: item.label,
        excludeFromSemantics: true,
        triggerMode: TooltipTriggerMode.longPress,
        child: AnimatedContainer(
          duration: FloatingPillNavBar.duration,
          curve: FloatingPillNavBar.curve,
          decoration: ShapeDecoration(
            shape: shape,
            color: selected
                ? scheme.secondaryContainer
                : scheme.secondaryContainer.withValues(alpha: 0),
          ),
          // Matériau transparent au-dessus du fond : l'ondulation reste visible.
          child: Material(
            type: MaterialType.transparency,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: shape,
              onTap: onTap,
              child: AnimatedPadding(
                duration: FloatingPillNavBar.duration,
                curve: FloatingPillNavBar.curve,
                padding: EdgeInsets.symmetric(
                  horizontal: selected ? _expandedPadding : _collapsedPadding,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (Widget child, Animation<double> animation) =>
                          ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: Icon(
                        selected ? item.selectedIcon : item.icon,
                        key: ValueKey<bool>(selected),
                        size: _iconSize,
                        color: foreground,
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: FloatingPillNavBar.duration,
                      switchInCurve: FloatingPillNavBar.curve,
                      // Courbe inverse : le titre qui se replie et celui qui
                      // se déplie restent complémentaires à chaque image, la
                      // largeur totale ne dépasse jamais la barre.
                      switchOutCurve: FloatingPillNavBar.curve.flipped,
                      layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previous, if (current != null) current],
                      ),
                      transitionBuilder: (Widget child, Animation<double> animation) =>
                          FadeTransition(
                        opacity: animation,
                        child: SizeTransition(
                          sizeFactor: animation,
                          axis: Axis.horizontal,
                          alignment: AlignmentDirectional.centerStart,
                          // Hauteur = celle du titre (sinon toute la place).
                          fixedCrossAxisSizeFactor: 1,
                          child: child,
                        ),
                      ),
                      child: selected
                          ? Padding(
                              key: const ValueKey<String>('label'),
                              padding: const EdgeInsets.only(left: _labelGap),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: maxLabelWidth),
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: foreground,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(key: ValueKey<String>('none')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
