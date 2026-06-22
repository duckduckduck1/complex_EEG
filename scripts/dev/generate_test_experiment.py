"""Генератор тестового пакета эксперимента.

Создаёт валидный пакет (`signal.bin` + `experiment.json`) по контракту
`docs/reference/experiment_package.md`, чтобы прогонять серверный upload flow
без реального устройства и Flutter-приложения.

Запуск:

    python scripts/dev/generate_test_experiment.py --out ./tmp_exp
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import uuid
from pathlib import Path


SAMPLE_RATE_HZ = 250
_SAMPLE = struct.Struct("<i")  # int32 little-endian — формат signal.bin


def _synthetic_signal(sample_count: int) -> bytes:
    """Синтетический сигнал: сумма синусоид, амплитуда в мкВ, int32 LE."""

    out = bytearray()
    for n in range(sample_count):
        t = n / SAMPLE_RATE_HZ
        value = 50.0 * math.sin(2 * math.pi * 10.0 * t) + 20.0 * math.sin(2 * math.pi * 3.0 * t)
        out += _SAMPLE.pack(int(round(value)))
    return bytes(out)


def _build_segments(sample_count: int, segment_count: int) -> list[dict]:
    """Делит сигнал на смежные непересекающиеся сегменты `seg_1..seg_N`."""

    segment_count = max(1, min(segment_count, sample_count))
    step = sample_count // segment_count
    segments: list[dict] = []
    start = 0
    for i in range(1, segment_count + 1):
        end = sample_count if i == segment_count else start + step
        segments.append({"segment_id": f"seg_{i}", "start_sample": start, "end_sample": end})
        start = end
    return segments


def build_experiment_package(
    out_dir: str | Path,
    *,
    experiment_id: str | None = None,
    sample_count: int = 2500,
    segment_count: int = 1,
    animal_id: str = "mouse_1",
    with_optional: bool = False,
) -> dict:
    """Создаёт пакет эксперимента в `out_dir`, возвращает содержимое experiment.json."""

    if sample_count < 2:
        raise ValueError("sample_count must be >= 2")

    experiment_id = experiment_id or f"exp_{uuid.uuid4().hex}"
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)

    (out / "signal.bin").write_bytes(_synthetic_signal(sample_count))

    segments = _build_segments(sample_count, segment_count)
    first_end = segments[0]["end_sample"]
    experiment = {
        "experiment_id": experiment_id,
        "display_name": experiment_id,
        "metadata": {"animal_id": animal_id},
        "recording": {
            "sample_rate_hz": SAMPLE_RATE_HZ,
            "adc": "MAX30003",
            "amplitude_unit": "microvolts",
            "sample_encoding": "int32_le",
        },
        "segments": segments,
        "gaps": [],
        "labels": [{"segment_id": "seg_1", "sample_index": first_end // 2, "label": "nrem"}],
        "fbm_events": [{"segment_id": "seg_1", "sample_index": first_end // 4}],
    }
    (out / "experiment.json").write_text(
        json.dumps(experiment, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    if with_optional:
        (out / "journal.ndjson").write_text(
            json.dumps({"type": "experiment_started", "global_sample_index": 0}, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        (out / "app.log").write_text("test experiment package\n", encoding="utf-8")

    return experiment


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate a valid EEG test experiment package")
    parser.add_argument("--out", required=True, help="output directory for the package")
    parser.add_argument("--experiment-id", default=None, help="experiment_id (default: exp_<uuid>)")
    parser.add_argument(
        "--samples", type=int, default=2500, help="number of int32 samples (default 2500 = 10s @ 250 Hz)"
    )
    parser.add_argument("--segments", type=int, default=1, help="number of contiguous segments")
    parser.add_argument("--animal-id", default="mouse_1")
    parser.add_argument(
        "--with-optional", action="store_true", help="also write journal.ndjson and app.log"
    )
    args = parser.parse_args()

    experiment = build_experiment_package(
        args.out,
        experiment_id=args.experiment_id,
        sample_count=args.samples,
        segment_count=args.segments,
        animal_id=args.animal_id,
        with_optional=args.with_optional,
    )
    print(f"Generated experiment {experiment['experiment_id']} in {args.out}")


if __name__ == "__main__":
    main()
