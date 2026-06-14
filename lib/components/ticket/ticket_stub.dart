import 'package:flutter/material.dart';

/// Right-edge sliver. Distinct constructors model the four flavours; each
/// carries the data it needs to render.
sealed class TicketStub {
  const TicketStub();
  const factory TicketStub.none() = StubNone;
  const factory TicketStub.admitOne() = StubAdmitOne;
  const factory TicketStub.repeatedTitle([String? overrideText]) = StubRepeated;
  const factory TicketStub.serialCode([String? overrideText]) = StubSerial;
}

class StubNone extends TicketStub {
  const StubNone();
}

class StubAdmitOne extends TicketStub {
  const StubAdmitOne();
}

class StubRepeated extends TicketStub {
  final String? overrideText;
  const StubRepeated([this.overrideText]);
}

class StubSerial extends TicketStub {
  final String? overrideText;
  const StubSerial([this.overrideText]);
}

/// Visible width of the stub sliver. The Rohling reserves this space regardless
/// of variant so the perforation line lands consistently across styles.
const double kStubWidth = 60;

/// Width of zero when there is no stub.
double widthFor(TicketStub stub) => stub is StubNone ? 0 : kStubWidth;

/// Renders the stub contents. The Rohling already provides the bordered slot.
/// `titleHint` is the body title, available to stubs that echo it.
class TicketStubContent extends StatelessWidget {
  final TicketStub stub;
  final String titleHint;
  final TextStyle textStyle;
  const TicketStubContent({
    super.key,
    required this.stub,
    required this.titleHint,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final s = stub;
    final String text;
    switch (s) {
      case StubNone():
        return const SizedBox.shrink();
      case StubAdmitOne():
        text = 'ADMIT ONE';
        break;
      case StubRepeated(:final overrideText):
        text = (overrideText ?? titleHint).toUpperCase();
        break;
      case StubSerial(:final overrideText):
        text = (overrideText ?? 'PICK').toUpperCase();
        break;
    }
    return Center(
      child: RotatedBox(
        quarterTurns: 3,
        child: Text(
          text,
          style: textStyle.copyWith(letterSpacing: 4, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}
