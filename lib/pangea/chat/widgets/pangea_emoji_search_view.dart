import 'package:flutter/material.dart';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

class PangeaEmojiSearchView extends SearchView {
  const PangeaEmojiSearchView(
    super.config,
    super.state,
    super.showEmojiView, {
    super.key,
  });

  @override
  PangeaEmojiSearchViewState createState() => PangeaEmojiSearchViewState();
}

class PangeaEmojiSearchViewState extends SearchViewState {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final emojiSize = widget.config.emojiViewConfig.getEmojiSize(
          constraints.maxWidth,
        );
        final emojiBoxSize = widget.config.emojiViewConfig.getEmojiBoxSize(
          constraints.maxWidth,
        );

        return Container(
          color: widget.config.searchViewConfig.backgroundColor,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      widget.showEmojiView();
                    },
                    color: widget.config.searchViewConfig.buttonIconColor,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: TextField(
                      onChanged: onTextInputChanged,
                      focusNode: focusNode,
                      style: widget.config.searchViewConfig.inputTextStyle,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: widget.config.searchViewConfig.hintText,
                        hintStyle: widget.config.searchViewConfig.hintTextStyle,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Material(
                  color: Theme.of(context).colorScheme.onInverseSurface,
                  child: EmojiContainer(
                    color: widget.config.emojiViewConfig.backgroundColor,
                    buttonMode: widget.config.emojiViewConfig.buttonMode,
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        childAspectRatio: 1,
                        crossAxisCount: widget.config.emojiViewConfig.columns,
                        mainAxisSpacing:
                            widget.config.emojiViewConfig.verticalSpacing,
                        crossAxisSpacing:
                            widget.config.emojiViewConfig.horizontalSpacing,
                      ),
                      scrollDirection: Axis.vertical,
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        return buildEmoji(
                          results[index],
                          emojiSize,
                          emojiBoxSize,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
