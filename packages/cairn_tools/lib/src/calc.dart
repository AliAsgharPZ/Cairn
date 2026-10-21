/// A small, safe arithmetic evaluator: numbers, `+ - * / % ^`, parentheses
/// and unary minus. No `eval`, no identifiers, no side effects — an
/// expression either produces a number or a [FormatException] with the
/// offending position. Used by the `calc.eval` tool.
library;

import 'dart:math' as math;

sealed class _Tok {
  const _Tok(this.pos);
  final int pos;
}

class _Num extends _Tok {
  const _Num(super.pos, this.value);
  final double value;
}

class _Op extends _Tok {
  const _Op(super.pos, this.op);
  final String op;
}

List<_Tok> _tokenize(String input) {
  final toks = <_Tok>[];
  var i = 0;
  while (i < input.length) {
    final ch = input[i];
    if (ch == ' ' || ch == '\t' || ch == '\n') {
      i++;
      continue;
    }
    if ('+-*/%^()'.contains(ch)) {
      toks.add(_Op(i, ch));
      i++;
      continue;
    }
    final isDigit = ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;
    if (isDigit || ch == '.') {
      final start = i;
      var seenDot = false;
      while (i < input.length) {
        final c = input[i];
        if (c == '.') {
          if (seenDot) {
            throw FormatException('Invalid number', input, i);
          }
          seenDot = true;
          i++;
        } else if (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39) {
          i++;
        } else {
          break;
        }
      }
      final text = input.substring(start, i);
      final value = double.tryParse(text);
      if (value == null) {
        throw FormatException('Invalid number "$text"', input, start);
      }
      toks.add(_Num(start, value));
      continue;
    }
    throw FormatException('Unexpected character "$ch"', input, i);
  }
  return toks;
}

class _Parser {
  _Parser(this.toks, this.input);
  final List<_Tok> toks;
  final String input;
  var _i = 0;

  _Tok? get _peek => _i < toks.length ? toks[_i] : null;

  double parse() {
    final v = _expr();
    if (_i != toks.length) {
      throw FormatException('Unexpected trailing input', input, toks[_i].pos);
    }
    return v;
  }

  // expr := term (('+'|'-') term)*
  double _expr() {
    var v = _term();
    while (_peek is _Op && ((_peek as _Op).op == '+' || (_peek as _Op).op == '-')) {
      final op = (_peek as _Op).op;
      _i++;
      final rhs = _term();
      v = op == '+' ? v + rhs : v - rhs;
    }
    return v;
  }

  // term := unary (('*'|'/'|'%') unary)*
  double _term() {
    var v = _unary();
    while (_peek is _Op &&
        ((_peek as _Op).op == '*' || (_peek as _Op).op == '/' || (_peek as _Op).op == '%')) {
      final opTok = _peek as _Op;
      _i++;
      final rhs = _unary();
      switch (opTok.op) {
        case '*':
          v = v * rhs;
        case '/':
          if (rhs == 0) {
            throw FormatException('Division by zero', input, opTok.pos);
          }
          v = v / rhs;
        case '%':
          if (rhs == 0) {
            throw FormatException('Modulo by zero', input, opTok.pos);
          }
          v = v % rhs;
      }
    }
    return v;
  }

  // unary := '-' unary | power
  double _unary() {
    if (_peek is _Op && (_peek as _Op).op == '-') {
      _i++;
      return -_unary();
    }
    if (_peek is _Op && (_peek as _Op).op == '+') {
      _i++;
      return _unary();
    }
    return _power();
  }

  // power := atom ('^' unary)?   (right-associative)
  double _power() {
    final base = _atom();
    if (_peek is _Op && (_peek as _Op).op == '^') {
      _i++;
      final exp = _unary();
      return math.pow(base, exp).toDouble();
    }
    return base;
  }

  // atom := number | '(' expr ')'
  double _atom() {
    final tok = _peek;
    if (tok is _Num) {
      _i++;
      return tok.value;
    }
    if (tok is _Op && tok.op == '(') {
      _i++;
      final v = _expr();
      final closing = _peek;
      if (closing is! _Op || closing.op != ')') {
        throw FormatException('Missing closing parenthesis', input, tok.pos);
      }
      _i++;
      return v;
    }
    throw FormatException('Expected a number or "("', input, tok?.pos ?? input.length);
  }
}

/// Evaluates [expression] and returns the numeric result.
/// Throws [FormatException] for malformed input or division by zero.
double evaluateExpression(String expression) {
  final toks = _tokenize(expression);
  if (toks.isEmpty) {
    throw const FormatException('Empty expression');
  }
  return _Parser(toks, expression).parse();
}

/// Formats a result without a trailing `.0` for integral values.
String formatNumber(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) {
    return v.round().toString();
  }
  return v.toString();
}
