from __future__ import annotations


def character_error_rate(expected: str, actual: str) -> float:
    if not expected and not actual:
        return 0.0
    if not expected:
        return 1.0

    distance = _levenshtein_distance(expected, actual)
    return distance / max(len(expected), len(actual), 1)


def _levenshtein_distance(left: str, right: str) -> int:
    if left == right:
        return 0
    if not left:
        return len(right)
    if not right:
        return len(left)

    previous = list(range(len(right) + 1))
    for left_index, left_char in enumerate(left, start=1):
        current = [left_index]
        for right_index, right_char in enumerate(right, start=1):
            insertion = current[right_index - 1] + 1
            deletion = previous[right_index] + 1
            substitution = previous[right_index - 1] + (left_char != right_char)
            current.append(min(insertion, deletion, substitution))
        previous = current

    return previous[-1]

