import 'dart:ui';

import 'package:appflowy_editor/src/core/document/attributes.dart';
import 'package:appflowy_editor/src/core/document/node.dart';
import 'package:appflowy_editor/src/core/document/text_delta.dart';
import 'package:appflowy_editor/src/core/location/position.dart';
import 'package:appflowy_editor/src/core/location/selection.dart';
import 'package:appflowy_editor/src/editor_state.dart';
import 'package:appflowy_editor/src/editor/block_component/rich_text/appflowy_rich_text_keys.dart';
import 'package:appflowy_editor/src/render/selection/selectable.dart';
import 'package:appflowy_editor/src/extensions/text_style_extension.dart';
import 'package:appflowy_editor/src/editor/util/color_util.dart';
import 'package:appflowy_editor/src/core/document/path.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

typedef TextSpanDecoratorForAttribute = InlineSpan Function(
  BuildContext context,
  Node node,
  int index,
  TextInsert text,
  TextSpan textSpan,
);

typedef AppFlowyTextSpanDecorator = TextSpan Function(TextSpan textSpan);

class AppFlowyRichText extends StatefulWidget {
  const AppFlowyRichText({
    super.key,
    this.cursorHeight,
    this.cursorWidth = 1.5,
    this.lineHeight,
    this.textSpanDecorator,
    this.placeholderText = ' ',
    this.placeholderTextSpanDecorator,
    this.textDirection = TextDirection.ltr,
    this.textSpanDecoratorForCustomAttributes,
    required this.node,
    required this.editorState,
  });

  /// The node of the rich text.
  final Node node;

  /// The editor state.
  final EditorState editorState;

  /// The height of the cursor.
  ///
  /// If this is null, the height of the cursor will be calculated automatically.
  final double? cursorHeight;

  /// The width of the cursor.
  final double cursorWidth;

  /// The height of each line.
  final double? lineHeight;

  /// customize the text span for rich text
  final AppFlowyTextSpanDecorator? textSpanDecorator;

  /// The placeholder text when the rich text is empty.
  final String placeholderText;

  /// customize the text span for placeholder text
  final AppFlowyTextSpanDecorator? placeholderTextSpanDecorator;

  /// customize the text span for custom attributes
  ///
  /// You can use this to customize the text span for custom attributes
  ///   or override the existing one.
  final TextSpanDecoratorForAttribute? textSpanDecoratorForCustomAttributes;
  final TextDirection textDirection;

  @override
  State<AppFlowyRichText> createState() => _AppFlowyRichTextState();
}

class _AppFlowyRichTextState extends State<AppFlowyRichText>
    with SelectableMixin {
  final textKey = GlobalKey();
  final placeholderTextKey = GlobalKey();

  RenderParagraph get _renderParagraph =>
      textKey.currentContext?.findRenderObject() as RenderParagraph;

  RenderParagraph? get _placeholderRenderParagraph =>
      placeholderTextKey.currentContext?.findRenderObject() as RenderParagraph?;

  TextSpanDecoratorForAttribute? get textSpanDecoratorForAttribute =>
      widget.textSpanDecoratorForCustomAttributes ??
      widget.editorState.editorStyle.textSpanDecorator;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: widget.node.delta?.toPlainText().isEmpty ?? true
          ? Stack(
              children: [
                _buildPlaceholderText(context),
                _buildRichText(context),
              ],
            )
          : _buildRichText(context),
    );
  }

  @override
  Position start() => Position(path: widget.node.path, offset: 0);

  @override
  Position end() => Position(
        path: widget.node.path,
        offset: widget.node.delta?.toPlainText().length ?? 0,
      );

  @override
  Rect getBlockRect() {
    throw UnimplementedError();
  }

  @override
  Rect? getCursorRectInPosition(Position position) {
    final textPosition = TextPosition(offset: position.offset);

    var cursorHeight = _renderParagraph.getFullHeightForCaret(textPosition);
    var cursorOffset =
        _renderParagraph.getOffsetForCaret(textPosition, Rect.zero);
    if (cursorHeight == null) {
      cursorHeight =
          _placeholderRenderParagraph?.getFullHeightForCaret(textPosition);
      cursorOffset = _placeholderRenderParagraph?.getOffsetForCaret(
            textPosition,
            Rect.zero,
          ) ??
          Offset.zero;
      if (textDirection() == TextDirection.rtl) {
        if (widget.placeholderText.trim().isNotEmpty) {
          cursorOffset = cursorOffset.translate(
            _placeholderRenderParagraph?.size.width ?? 0,
            0,
          );
        }
      }
    }
    if (widget.cursorHeight != null && cursorHeight != null) {
      cursorOffset = Offset(
        cursorOffset.dx,
        cursorOffset.dy + (cursorHeight - widget.cursorHeight!) / 2,
      );
      cursorHeight = widget.cursorHeight;
    }
    final rect = Rect.fromLTWH(
      cursorOffset.dx - (widget.cursorWidth / 2.0),
      cursorOffset.dy,
      widget.cursorWidth,
      cursorHeight ?? 16.0,
    );
    return rect;
  }

  @override
  Position getPositionInOffset(Offset start) {
    final offset = _renderParagraph.globalToLocal(start);
    final baseOffset = _renderParagraph.getPositionForOffset(offset).offset;
    return Position(path: widget.node.path, offset: baseOffset);
  }

  @override
  Selection? getWordBoundaryInOffset(Offset offset) {
    final localOffset = _renderParagraph.globalToLocal(offset);
    final textPosition = _renderParagraph.getPositionForOffset(localOffset);
    final textRange = _renderParagraph.getWordBoundary(textPosition);
    final start = Position(path: widget.node.path, offset: textRange.start);
    final end = Position(path: widget.node.path, offset: textRange.end);
    return Selection(start: start, end: end);
  }

  @override
  Selection? getWordBoundaryInPosition(Position position) {
    final textPosition = TextPosition(offset: position.offset);
    final textRange = _renderParagraph.getWordBoundary(textPosition);
    final start = Position(path: widget.node.path, offset: textRange.start);
    final end = Position(path: widget.node.path, offset: textRange.end);
    return Selection(start: start, end: end);
  }

  @override
  List<Rect> getRectsInSelection(Selection selection) {
    final textSelection = textSelectionFromEditorSelection(selection);
    if (textSelection == null) {
      return [];
    }
    final rects = _renderParagraph
        .getBoxesForSelection(textSelection, boxHeightStyle: BoxHeightStyle.max)
        .map((box) => box.toRect())
        .toList(growable: false);
    if (rects.isEmpty) {
      // If the rich text widget does not contain any text,
      // there will be no selection boxes,
      // so we need to return to the default selection.
      return [Rect.fromLTWH(0, 0, 0, _renderParagraph.size.height)];
    }
    return rects;
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) {
    final localStart = _renderParagraph.globalToLocal(start);
    final localEnd = _renderParagraph.globalToLocal(end);
    final baseOffset = _renderParagraph.getPositionForOffset(localStart).offset;
    final extentOffset = _renderParagraph.getPositionForOffset(localEnd).offset;
    return Selection.single(
      path: widget.node.path,
      startOffset: baseOffset,
      endOffset: extentOffset,
    );
  }

  @override
  Offset localToGlobal(Offset offset) {
    return _renderParagraph.localToGlobal(offset);
  }

  @override
  TextDirection textDirection() {
    return widget.textDirection;
  }

  Widget _buildPlaceholderText(BuildContext context) {
    final textSpan = getPlaceholderTextSpan();
    return RichText(
      key: placeholderTextKey,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
      text: widget.placeholderTextSpanDecorator != null
          ? widget.placeholderTextSpanDecorator!(textSpan)
          : textSpan,
      textDirection: textDirection(),
    );
  }

  Widget _buildRichText(BuildContext context) {
    final textSpan = getTextSpan();
    return RichText(
      key: textKey,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
      text: widget.textSpanDecorator != null
          ? widget.textSpanDecorator!(textSpan)
          : textSpan,
      textDirection: textDirection(),
    );
  }

  TextSpan getPlaceholderTextSpan() {
    final style = widget.editorState.editorStyle.textStyleConfiguration;
    return TextSpan(
      children: [
        TextSpan(
          text: widget.placeholderText,
          style: style.text.copyWith(height: widget.lineHeight),
        ),
      ],
    );
  }

  TextSpan getTextSpan() {
    int offset = 0;
    List<InlineSpan> textSpans = [];
    final style = widget.editorState.editorStyle.textStyleConfiguration;
    final textInserts = widget.node.delta!.whereType<TextInsert>();
    for (final textInsert in textInserts) {
      TextStyle textStyle = style.text.copyWith(height: widget.lineHeight);
      final attributes = textInsert.attributes;
      if (attributes != null) {
        if (attributes.bold == true) {
          textStyle = textStyle.combine(style.bold);
        }
        if (attributes.italic == true) {
          textStyle = textStyle.combine(style.italic);
        }
        if (attributes.underline == true) {
          textStyle = textStyle.combine(style.underline);
        }
        if (attributes.strikethrough == true) {
          textStyle = textStyle.combine(style.strikethrough);
        }
        if (attributes.href != null) {
          textStyle = textStyle.combine(style.href);
        }
        if (attributes.code == true) {
          textStyle = textStyle.combine(style.code);
        }
        if (attributes.backgroundColor != null) {
          textStyle = textStyle.combine(
            TextStyle(backgroundColor: attributes.backgroundColor),
          );
        }
        if (attributes.color != null) {
          textStyle = textStyle.combine(
            TextStyle(color: attributes.color),
          );
        }
      }
      final textSpan = TextSpan(
        text: textInsert.text,
        style: textStyle,
      );
      textSpans.add(
        textSpanDecoratorForAttribute != null
            ? textSpanDecoratorForAttribute!(
                context,
                widget.node,
                offset,
                textInsert,
                textSpan,
              )
            : textSpan,
      );
      offset += textInsert.length;
    }
    return TextSpan(
      children: textSpans,
    );
  }

  TextSelection? textSelectionFromEditorSelection(Selection? selection) {
    if (selection == null) {
      return null;
    }

    final normalized = selection.normalized;
    final path = widget.node.path;
    if (path < normalized.start.path || path > normalized.end.path) {
      return null;
    }

    final length = widget.node.delta?.length;
    if (length == null) {
      return null;
    }

    TextSelection? textSelection;

    if (normalized.isSingle) {
      if (path.equals(normalized.start.path)) {
        if (normalized.isCollapsed) {
          textSelection = TextSelection.collapsed(
            offset: normalized.startIndex,
          );
        } else {
          textSelection = TextSelection(
            baseOffset: normalized.startIndex,
            extentOffset: normalized.endIndex,
          );
        }
      }
    } else {
      if (path.equals(normalized.start.path)) {
        textSelection = TextSelection(
          baseOffset: normalized.startIndex,
          extentOffset: length,
        );
      } else if (path.equals(normalized.end.path)) {
        textSelection = TextSelection(
          baseOffset: 0,
          extentOffset: normalized.endIndex,
        );
      } else {
        textSelection = TextSelection(
          baseOffset: 0,
          extentOffset: length,
        );
      }
    }
    return textSelection;
  }
}

extension AppFlowyRichTextAttributes on Attributes {
  bool get bold => this[AppFlowyRichTextKeys.bold] == true;

  bool get italic => this[AppFlowyRichTextKeys.italic] == true;

  bool get underline => this[AppFlowyRichTextKeys.underline] == true;

  bool get code => this[AppFlowyRichTextKeys.code] == true;

  bool get strikethrough {
    return (containsKey(AppFlowyRichTextKeys.strikethrough) &&
        this[AppFlowyRichTextKeys.strikethrough] == true);
  }

  Color? get color {
    final textColor = this[AppFlowyRichTextKeys.textColor] as String?;
    return textColor?.toColor();
  }

  Color? get backgroundColor {
    final highlightColor = this[AppFlowyRichTextKeys.highlightColor] as String?;
    return highlightColor?.toColor();
  }

  String? get href {
    if (this[AppFlowyRichTextKeys.href] is String) {
      return this[AppFlowyRichTextKeys.href];
    }
    return null;
  }
}
