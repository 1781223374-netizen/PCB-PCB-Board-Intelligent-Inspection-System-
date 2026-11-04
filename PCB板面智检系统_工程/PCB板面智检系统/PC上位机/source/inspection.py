"""Per-board evidence and temporal confirmation, independent of Qt and transport."""
from dataclasses import asdict, dataclass
import math
import uuid


@dataclass(frozen=True)
class Parameters:
    k: float = 6.5
    min_area: int = 180
    min_peak: float = 16.0
    fixed_threshold: float | None = None
    window_s: float = 20.0
    confirm_s: float = 15.0
    confirm_area: int = 300
    confirm_peak: float = 22.0
    min_rate: float = 0.8
    min_fraction: float = 0.6
    edge_margin: int = 12
    refine: bool = False
    use_variation: bool = True
    variation_cap: float = 30.0

    small_structure_response: float = 12.0
    surface_mode: bool = False
    scratch_min_length: float = 18.0
    scratch_response: float = 2.5
    structure_tolerance: int = 2
    mask_mount_holes: bool = True

    def validate(self):
        if any(not math.isfinite(v) for v in asdict(self).values() if v is not None):
            raise ValueError('检测参数必须为有限数值')
        if not (0.1 <= self.k <= 20 and 1 <= self.min_area <= 100000
                and 0 <= self.min_peak <= 255):
            raise ValueError('灵敏度、面积或峰值超出范围')
        if self.fixed_threshold is not None and not 0 < self.fixed_threshold <= 255:
            raise ValueError('差分阈值必须大于 0 且不超过 255')
        if not (1 <= self.confirm_s < self.window_s <= 180):
            raise ValueError('观察时间必须大于确认持续时间')
        if self.confirm_area < self.min_area or self.confirm_peak < self.min_peak:
            raise ValueError('确认面积/峰值应不小于单帧面积/峰值')
        if not (0 < self.min_fraction <= 1 and 0 < self.min_rate <= 20):
            raise ValueError('时序命中参数超出范围')
        if not (8 <= self.edge_margin <= 80 and 0 <= self.variation_cap <= 100):
            raise ValueError('保护带为 8–80 画布像素；波动上限为 0–100')
        if type(self.surface_mode) is not bool or type(self.mask_mount_holes) is not bool:
            raise ValueError('检测模式开关无效')
        if not (8 <= self.scratch_min_length <= 200 and .5 <= self.scratch_response <= 30
                and 0 <= self.structure_tolerance <= 8 and 3<=self.small_structure_response<=100):
            raise ValueError('细线长度、响应或结构容差超出范围')
        return self


@dataclass
class Track:
    box: tuple
    raw_box: tuple
    first: float
    last: float
    born_index: int
    hits: int
    area: int
    peak: float
    strong_first: float | None = None
    strong_last: float | None = None
    strong_hits: int = 0
    strong_born_index: int = 0
    review_marked: bool = False

    kind: str = "legacy"
    length: float = 0.0

    def snapshot(self):
        return {'box': list(self.raw_box), 'canonical_box': list(self.box),
                'span_s': round(self.last-self.first, 3), 'hits': self.hits,
                'area': self.area, 'peak': self.peak, 'kind': self.kind, 'length': round(self.length,2)}


class BoardSession:
    """Wall-clock time never substitutes for valid observations.

    Result is terminal. A new board always requires a new session. Tracking is
    in registered template coordinates; raw coordinates are retained for review.
    """
    def __init__(self, params: Parameters, now: float):
        self.params = params.validate()
        self.id = uuid.uuid4().hex[:12]
        self.started = now
        self.state = 'running'
        self.reason = ''
        self.tracks = []
        self.confirmed = []
        self.review_evidence = []
        self.valid_s = 0.0
        self.valid_frames = 0
        self.total_valid = 0
        self.invalid_frames = 0
        self.failures = 0
        self.last_valid = None
        self.seen = set()

    @property
    def minimum_frames(self):
        return max(4, math.ceil(self.params.window_s*self.params.min_rate))

    def invalidate(self, reason):
        if self.state == 'running':
            self.state, self.reason = 'invalid', reason
        return self.state

    def check_timeout(self, now):
        if self.state == 'running' and now-self.started > max(3*self.params.window_s, self.params.window_s+20):
            self.invalidate('有效检测不足，请检查板子、模板和图像流后重新开始')
        return self.state

    def update(self, result, timestamp, frame_key):
        if self.state != 'running' or frame_key in self.seen:
            return self.state
        self.seen.add(frame_key)
        if len(self.seen) > 2048:
            self.seen = {frame_key}
        if not result.ok:
            self.invalid_frames += 1
            self.failures += 1
            self.tracks.clear()
            self.last_valid = None
            self.valid_s, self.valid_frames = 0.0, 0
            if self.failures >= 3:
                self.invalidate('连续对齐失败或板面覆盖不足，请放稳板子并确认正反面模板')
            return self.state
        if self.last_valid is not None and timestamp <= self.last_valid:
            return self.state
        self.failures = 0
        if self.last_valid is not None:
            gap = timestamp-self.last_valid
            if gap > 2.0:
                self.tracks.clear()
                self.valid_s, self.valid_frames = 0.0, 0
            else:
                self.valid_s += gap
        self.last_valid = timestamp
        self.valid_frames += 1
        self.total_valid += 1
        # Prune before associating; a late result cannot revive an expired track.
        self.tracks = [t for t in self.tracks if timestamp-t.last <= 2.0]
        eligible = result.regions
        used = set()
        for region in eligible:
            box = tuple(region.canon_bbox or region.bbox)
            cx, cy = (box[0]+box[2])/2, (box[1]+box[3])/2
            choices = []
            for i, tr in enumerate(self.tracks):
                if tr.kind != getattr(region,'kind','legacy'):
                    continue
                if i in used:
                    continue
                tx, ty = (tr.box[0]+tr.box[2])/2, (tr.box[1]+tr.box[3])/2
                distance = math.hypot(cx-tx, cy-ty)
                if distance < 56.0:
                    choices.append((distance, i))
            if choices:
                _, i = min(choices)
                tr = self.tracks[i]
                tr.box, tr.raw_box, tr.last = box, tuple(region.bbox), timestamp
                tr.hits += 1
                tr.area = max(tr.area, region.area)
                tr.peak = max(tr.peak, region.peak)
                tr.length = max(tr.length,getattr(region,'length',0))
            else:
                tr = Track(box, tuple(region.bbox), timestamp, timestamp,
                           self.valid_frames, 1, region.area, region.peak,
                           kind=getattr(region,'kind','legacy'),length=getattr(region,'length',0))
                self.tracks.append(tr)
                i = len(self.tracks)-1
            used.add(i)
            kind=getattr(region,'kind','legacy')
            strong = (region.area >= self.params.confirm_area and region.peak >= self.params.confirm_peak)
            if self.params.surface_mode and kind=='scratch':
                strong = getattr(region,'length',0)>=self.params.scratch_min_length and region.peak>=self.params.scratch_response
            elif self.params.surface_mode and kind=='structure':
                strong=region.area>=20 and region.peak>=self.params.small_structure_response
            elif self.params.surface_mode and kind=='material':
                strong = region.area>=self.params.confirm_area
            if strong:
                if tr.strong_last is None or timestamp-tr.strong_last > 2.0:
                    tr.strong_first, tr.strong_hits, tr.strong_born_index = timestamp, 0, self.valid_frames
                tr.strong_last = timestamp
                tr.strong_hits += 1
        p = self.params
        for tr in self.tracks:
            span = tr.last-tr.first
            fraction = tr.hits/max(1, self.valid_frames-tr.born_index+1)
            if (not tr.review_marked and span >= min(3.0, p.confirm_s) and
                    tr.hits >= 3 and fraction >= p.min_fraction):
                self.review_evidence.append(tr.snapshot())
                tr.review_marked = True
            strong_span = 0 if tr.strong_first is None else tr.strong_last-tr.strong_first
            strong_fraction = tr.strong_hits/max(1, self.valid_frames-tr.strong_born_index+1)
            if (timestamp == tr.strong_last and strong_span >= p.confirm_s and
                    tr.strong_hits/max(1.0, strong_span) >= p.min_rate and strong_fraction >= p.min_fraction):
                self.confirmed.append(tr.snapshot())
        if self.confirmed:
            self.state = 'ng'
        elif self.valid_s >= p.window_s and self.valid_frames >= self.minimum_frames:
            self.state = 'review' if self.review_evidence else 'ok'
            if self.state == 'review':
                self.reason = '存在持续候选，但未达到确认条件；请复核候选区域'
        return self.state
