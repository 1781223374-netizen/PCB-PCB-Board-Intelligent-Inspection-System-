#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PCB AOI 核心引擎（模板标定 + 比对检测）
=====================================
设计要点
--------
* **不需要 Gerber**：第一帧良品图当几何基准，后续帧 SIFT 配准到它
* 标定：采集 N 帧良品 → 逐帧配准到基准帧 → 变换到统一画布 → 逐像素中位数 = 模板
* 检测：被测帧配准 → 归一化 → 与模板差分（允许 ±2px 局部错位）→ 稳健阈值 → 可疑区域
* 区域坐标可**反算回原始帧**，直接画在画面上

对外接口
--------
    tm = TemplateMatcher()
    tm.start_calibration()
    while calibrating: tm.feed_calibration(frame_bgr)   # 返回 (完成?, 已收/需要)
    info = tm.finalize()                               # 模板一致性等
    res  = tm.detect(frame_bgr, k=6.0, min_area=150, min_peak=18.0)
    tm.save(path) / TemplateMatcher.load(path)
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

import cv2
import numpy as np

SHIFT = 1
CANON_W = 1180


@dataclass
class Region:
    bbox: tuple            # 原始帧坐标 (x1,y1,x2,y2)
    area: int
    peak: float
    canon_bbox: tuple | None = None
    kind: str = "legacy"
    length: float = 0.0


@dataclass
class DetectResult:
    ok: bool
    regions: list = field(default_factory=list)
    thr: float = 0.0
    align_inliers: int = 0
    align_err: float = 99.0
    reason: str = ""
    coverage_mask: np.ndarray | None = None
    threshold_max: float = 0.0
    refined: bool = False
    normal_groups: int = 0
    surface_info: dict = field(default_factory=dict)


def erode_mask(mask, radius):
    return cv2.erode(mask, np.ones((2*radius+1, 2*radius+1), np.uint8),
                     borderType=cv2.BORDER_CONSTANT, borderValue=0)


def shifted_images(image):
    height, width = image.shape
    return [cv2.warpAffine(image, np.float32([[1, 0, dx], [0, 1, dy]]), (width, height),
                flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
            for dy in range(-SHIFT, SHIFT+1) for dx in range(-SHIFT, SHIFT+1)]


def order_quad(pts: np.ndarray) -> np.ndarray:
    s = pts.sum(axis=1)
    d = np.diff(pts, axis=1).ravel()
    return np.array([pts[np.argmin(s)], pts[np.argmin(d)],
                     pts[np.argmax(s)], pts[np.argmax(d)]], dtype=np.float32)


def find_board_quad(bgr: np.ndarray):
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (5, 5), 0)
    _, th = cv2.threshold(blur, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    th = cv2.morphologyEx(th, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    cnts, _ = cv2.findContours(th, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not cnts:
        return None
    c = max(cnts, key=cv2.contourArea)
    if cv2.contourArea(c) < 0.05 * gray.size:
        return None
    rect = cv2.minAreaRect(c)
    return order_quad(cv2.boxPoints(rect).astype(np.float32))


def sift_h(src_gray, dst_gray, nfeat=4000, reference=None):
    clahe = cv2.createCLAHE(2.0, (8, 8))
    b = clahe.apply(dst_gray)
    sift = cv2.SIFT_create(nfeatures=nfeat)
    k1, d1 = reference if reference is not None else sift.detectAndCompute(clahe.apply(src_gray), None)
    k2, d2 = sift.detectAndCompute(b, None)
    if d1 is None or d2 is None or len(k1) < 20 or len(k2) < 20:
        return None, 0, 99.0
    bf = cv2.BFMatcher(cv2.NORM_L2)
    good = [pair[0] for pair in bf.knnMatch(d1, d2, k=2)
            if len(pair) == 2 and pair[0].distance < 0.75 * pair[1].distance]
    if len(good) < 15:
        return None, 0, 99.0
    src = np.float32([k1[m.queryIdx].pt for m in good]).reshape(-1, 1, 2)
    dst = np.float32([k2[m.trainIdx].pt for m in good]).reshape(-1, 1, 2)
    H, inl = cv2.findHomography(src, dst, cv2.RANSAC, 4.0)
    if H is None:
        return None, 0, 99.0
    proj = cv2.perspectiveTransform(src, H).reshape(-1, 2)
    err = np.linalg.norm(proj - dst.reshape(-1, 2), axis=1)[inl.ravel() > 0]
    return H, int(inl.sum()), float(np.median(err)) if err.size else 99.0


def board_mask_of(canon: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(canon, cv2.COLOR_BGR2GRAY)
    m = (gray < 200).astype(np.uint8) * 255
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
    cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not cnts:
        return np.zeros(gray.shape, np.uint8)
    out = np.zeros_like(m)
    cv2.drawContours(out, [max(cnts, key=cv2.contourArea)], -1, 255, -1)
    return out


def enhance_bgr(bgr, clip=2.5):
    """局部对比度增强（只动亮度，保持色相），对低对比画面提升缺陷可分辨性。"""
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    l = cv2.createCLAHE(clipLimit=clip, tileGridSize=(8, 8)).apply(l)
    return cv2.cvtColor(cv2.merge([l, a, b]), cv2.COLOR_LAB2BGR)


def normalize_to(img, ref, mask, tiles=6):
    out = img.astype(np.float32).copy()
    rf = ref.astype(np.float32)
    H, W = img.shape[:2]
    for c in range(3):
        xs, ys = [], []
        for ty in range(tiles):
            for tx in range(tiles):
                y0, y1 = H * ty // tiles, H * (ty + 1) // tiles
                x0, x1 = W * tx // tiles, W * (tx + 1) // tiles
                m = mask[y0:y1, x0:x1] > 0
                if m.sum() < 200:
                    continue
                xs.append(np.median(out[y0:y1, x0:x1, c][m]))
                ys.append(np.median(rf[y0:y1, x0:x1, c][m]))
        if len(xs) >= 3:
            xs, ys = np.array(xs), np.array(ys)
            A = np.vstack([xs, np.ones_like(xs)]).T
            sol, *_ = np.linalg.lstsq(A, ys, rcond=None)
            a, b = float(sol[0]), float(sol[1])
            a = min(max(a, 0.5), 2.0)
            out[:, :, c] = np.clip(a * out[:, :, c] + b, 0, 255)
    return np.clip(out, 0, 255).astype(np.uint8)


class TemplateMatcher:
    def __init__(self, enhance=True, clip=2.5):
        self.enhance = enhance
        self.clip = clip
        self.raw_tpl = None
        self.raw_good_groups = []
        self._surface_ref = None
        self.ref_bgr = None          # 基准帧
        self.ref_gray = None
        self.S = None                # 基准帧 -> 画布
        self.canon_h = 0
        self.tpl = None
        self.mask = None
        self.core = None
        self.tpl_gray = None
        self.shifted = []
        self.label = ""
        self.n_frames = 0
        self.consistency = None
        self.normal_groups = []
        self.normal_names = []
        self.normal_center = None
        self.normal_sigma = None
        self.normal_shifted = []
        self.ref_canon_gray = None
        self._good_samples = []
        self._good_raw = []
        self._good_need = 5
        self._ref_features = None
        # 标定状态
        self.calibrating = False
        self._cal_canons = []
        self._cal_raw = []
        self._cal_need = 20

    # ---------------- 标定 ----------------
    def start_calibration(self, need=20):
        self.calibrating = True
        self._cal_canons = []
        self._cal_raw = []
        self._cal_need = need
        self.ref_bgr = None
        self.ref_gray = None
        self._ref_features = None
        self.S = None
        return need

    def feed_calibration(self, bgr: np.ndarray):
        """喂一帧良品。返回 (是否完成, 已收帧数, 需要帧数)"""
        gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
        if self.ref_bgr is None:
            quad = find_board_quad(bgr)
            if quad is None:
                return False, len(self._cal_canons), self._cal_need
            w = float(np.linalg.norm(quad[1] - quad[0]) + np.linalg.norm(quad[2] - quad[3])) / 2
            h = float(np.linalg.norm(quad[3] - quad[0]) + np.linalg.norm(quad[2] - quad[1])) / 2
            ch = int(round(CANON_W * h / max(w, 1)))
            ch = max(200, min(ch, 1400))
            self.canon_h = ch
            dst = np.float32([[0, 0], [CANON_W - 1, 0],
                              [CANON_W - 1, ch - 1], [0, ch - 1]])
            self.S = cv2.getPerspectiveTransform(quad, dst)
            self.ref_bgr = bgr.copy()
            self.ref_gray = gray
            canon = cv2.warpPerspective(bgr, self.S, (CANON_W, ch))
            self._cal_raw.append(canon.copy())
            if self.enhance:
                canon = enhance_bgr(canon, self.clip)
            self._cal_canons.append(canon)
            return False, len(self._cal_canons), self._cal_need

        H, inl, err = self._align(gray)
        if H is None or inl < 25 or err > 4.0:
            return False, len(self._cal_canons), self._cal_need
        M = self.S @ np.linalg.inv(H)
        canon = cv2.warpPerspective(bgr, M, (CANON_W, self.canon_h),
                                    flags=cv2.INTER_LINEAR,
                                    borderMode=cv2.BORDER_CONSTANT, borderValue=(255, 255, 255))
        self._cal_raw.append(canon.copy())
        if self.enhance:
            canon = enhance_bgr(canon, self.clip)
        self._cal_canons.append(canon)
        if len(self._cal_canons) >= self._cal_need:
            info = self.finalize()
            return True, len(self._cal_canons), self._cal_need
        return False, len(self._cal_canons), self._cal_need

    def finalize(self):
        arr = np.stack([c.astype(np.float32) for c in self._cal_canons])
        tpl = np.median(arr, axis=0).astype(np.uint8)
        self.tpl = tpl
        self.raw_tpl = np.median(np.stack(self._cal_raw).astype(np.float32),axis=0).astype(np.uint8)
        self._surface_ref = None
        self.raw_good_groups = [self.raw_tpl.copy()]
        self.mask = board_mask_of(tpl)
        self.core = erode_mask(self.mask, 10) > 0
        g = cv2.cvtColor(tpl, cv2.COLOR_BGR2GRAY).astype(np.float32)
        self.tpl_gray = cv2.GaussianBlur(g, (0, 0), 2.1)
        self.shifted = []
        for dy in range(-SHIFT, SHIFT + 1):
            for dx in range(-SHIFT, SHIFT + 1):
                M = np.float32([[1, 0, dx], [0, 1, dy]])
                self.shifted.append(cv2.warpAffine(self.tpl_gray, M, (CANON_W, self.canon_h),
                                                   flags=cv2.INTER_LINEAR,
                                                   borderMode=cv2.BORDER_REPLICATE))
        diffs = [float(np.median(np.abs(cv2.cvtColor(c, cv2.COLOR_BGR2GRAY).astype(np.float32)
                                       - g)[self.core]))
                 for c in self._cal_canons]
        self.consistency = {"median": float(np.median(diffs)),
                            "p90": float(np.percentile(diffs, 90))}
        self.n_frames = len(self._cal_canons)
        self.normal_groups = [np.rint(self.tpl_gray).astype(np.uint8)]
        self.normal_names = ['初始良品标定']
        self._refresh_normal()
        self.calibrating = False
        self._cal_canons = []
        self._cal_raw = []
        return {"frames": self.n_frames, "canon": [CANON_W, self.canon_h],
                "consistency": self.consistency}

    # ---------------- 检测 ----------------
    def _align(self, gray):
        if self._ref_features is None:
            reference = cv2.createCLAHE(2.0, (8, 8)).apply(self.ref_gray)
            self._ref_features = cv2.SIFT_create(nfeatures=4000).detectAndCompute(reference, None)
        return sift_h(self.ref_gray, gray, reference=self._ref_features)

    def _refresh_normal(self):
        if self.ref_bgr is not None:
            raw = cv2.warpPerspective(self.ref_bgr, self.S, (CANON_W, self.canon_h))
            self.ref_canon_gray = cv2.cvtColor(raw, cv2.COLOR_BGR2GRAY)
        if len(self.normal_groups) >= 3:
            stack = np.stack(self.normal_groups).astype(np.float32)
            self.normal_center = np.median(stack, axis=0)
            sigma = 1.4826*np.median(np.abs(stack-self.normal_center), axis=0)
            self.normal_sigma = cv2.dilate(sigma, np.ones((3, 3), np.uint8))
            self.normal_shifted = shifted_images(self.normal_center)
        else:
            self.normal_center = self.normal_sigma = None
            self.normal_shifted = []

    def prepare_geometry(self, bgr, edge_margin=12, refine=False):
        gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
        H, inl, err = self._align(gray)
        if H is None or inl < 25 or err > 4.0:
            return None, DetectResult(False, reason='align', align_inliers=inl, align_err=err)
        M = self.S @ np.linalg.inv(H)
        size = (CANON_W, self.canon_h)
        canon = cv2.warpPerspective(bgr, M, size, flags=cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_CONSTANT, borderValue=(255, 255, 255))
        refined = False
        if refine and self.ref_canon_gray is not None:
            # Refine only a small residual translation. Do not fit a deformable
            # field that could remove a real scratch/line interruption.
            scale = 2
            target = cv2.resize(self.ref_canon_gray, None, fx=.5, fy=.5).astype(np.float32)/255
            moving = cv2.resize(cv2.cvtColor(canon, cv2.COLOR_BGR2GRAY), (target.shape[1], target.shape[0])).astype(np.float32)/255
            mask = cv2.resize(erode_mask(self.mask, 16), (target.shape[1], target.shape[0]), interpolation=cv2.INTER_NEAREST)
            warp = np.eye(2, 3, dtype=np.float32)
            try:
                _, warp = cv2.findTransformECC(target, moving, warp, cv2.MOTION_TRANSLATION,
                    (cv2.TERM_CRITERIA_COUNT | cv2.TERM_CRITERIA_EPS, 25, 1e-4), mask, 5)
                tx, ty = warp[:, 2]*scale
                if np.isfinite(warp).all() and max(abs(tx), abs(ty)) <= 2.0:
                    corrected = cv2.warpAffine(moving, warp, (moving.shape[1], moving.shape[0]),
                        flags=cv2.INTER_LINEAR | cv2.WARP_INVERSE_MAP, borderMode=cv2.BORDER_REPLICATE)
                    stable = mask > 0
                    def correlation(a, b):
                        a, b = a[stable], b[stable]
                        return float(np.mean((a-a.mean())*(b-b.mean()))/(a.std()*b.std()+1e-8))
                    before = correlation(target, moving)
                    after = correlation(target, corrected)
                    if after >= before:
                        correction = np.eye(3)
                        correction[0, 2], correction[1, 2] = -float(tx), -float(ty)
                        M = correction @ M
                        canon = cv2.warpPerspective(bgr, M, size, flags=cv2.INTER_LINEAR,
                            borderMode=cv2.BORDER_CONSTANT, borderValue=(255, 255, 255))
                        refined = True
            except cv2.error:
                pass
        valid = cv2.warpPerspective(np.full(bgr.shape[:2], 255, np.uint8), M, size,
            flags=cv2.INTER_NEAREST, borderMode=cv2.BORDER_CONSTANT, borderValue=0)
        board_core = erode_mask(self.mask, edge_margin) > 0
        core = board_core & (erode_mask(valid, edge_margin) > 0)
        if not board_core.any() or core.sum() < .9*board_core.sum():
            return None, DetectResult(False, reason='coverage', align_inliers=inl, align_err=err)
        return (canon, M, core, inl, err, refined), None

    def prepare_frame(self, bgr, edge_margin=12, refine=False):
        prepared, failure = self.prepare_geometry(bgr, edge_margin, refine)
        if failure:
            return None, failure
        canon, M, core, inl, err, refined = prepared
        if self.enhance:
            canon = enhance_bgr(canon, self.clip)
        norm = normalize_to(canon, self.tpl, self.mask)
        g1 = cv2.GaussianBlur(cv2.cvtColor(norm, cv2.COLOR_BGR2GRAY).astype(np.float32), (0, 0), 2.1)
        return (g1, M, core, inl, err, refined), None

    def start_good_sampling(self, need=5):
        if len(self.normal_groups) >= 12:
            raise ValueError('最多保存 12 组良品，请清空波动样本后重新采集')
        self._good_samples = []
        self._good_raw = []
        self._good_need = need

    def feed_good_sample(self, bgr, label='', edge_margin=12, refine=False):
        prepared, failure = self.prepare_frame(bgr, edge_margin, refine)
        if failure:
            return False, len(self._good_samples), self._good_need
        self._good_samples.append(np.rint(prepared[0]).astype(np.uint8))
        self._good_raw.append(cv2.warpPerspective(bgr,prepared[1],(CANON_W,self.canon_h),borderMode=cv2.BORDER_CONSTANT,borderValue=(255,255,255)))
        done = len(self._good_samples) >= self._good_need
        if done:
            self.normal_groups.append(np.median(np.stack(self._good_samples), axis=0).astype(np.uint8))
            self.normal_names.append(label or f'良品组 {len(self.normal_groups)}')
            self.raw_good_groups.append(np.median(np.stack(self._good_raw),axis=0).astype(np.uint8))
            self._surface_ref=None
            self._good_samples = []
            self._refresh_normal()
        return done, len(self._good_samples) if not done else self._good_need, self._good_need

    def clear_normal_groups(self):
        self.normal_groups = [np.rint(self.tpl_gray).astype(np.uint8)]
        self.normal_names = ['初始良品标定']
        self.raw_good_groups=[(self.raw_tpl if self.raw_tpl is not None else cv2.warpPerspective(self.ref_bgr,self.S,(CANON_W,self.canon_h))).copy()]
        self._surface_ref=None
        self._refresh_normal()

    def detect(self, bgr: np.ndarray, k=5.0, min_area=120, min_peak=10.0,
               min_inliers=25, max_err=4.0, fixed_threshold=None,
               edge_margin=12, refine=False, use_variation=True, variation_cap=30.0,
               surface_mode=False, scratch_min_length=18.0, scratch_response=2.5,
               structure_tolerance=2, mask_mount_holes=True, small_structure_response=12.0) -> DetectResult:
        if self.tpl is None:
            return DetectResult(False, reason="no_template")
        if not 8 <= int(edge_margin) <= 80 or not 0 <= variation_cap <= 100:
            raise ValueError('保护带或正常波动上限超出范围')
        if surface_mode:
            return self._detect_surface(bgr, edge_margin, refine, min_area,
                scratch_min_length, scratch_response, structure_tolerance, mask_mount_holes, use_variation, small_structure_response)
        prepared, failure = self.prepare_frame(bgr, int(edge_margin), refine)
        if failure:
            return failure
        g1, M, core, inl, err, refined = prepared
        if inl < min_inliers or err > max_err:
            return DetectResult(False, reason='align', align_inliers=inl, align_err=err)
        d = np.full(g1.shape, 1e9, np.float32)
        using_normal = use_variation and self.normal_center is not None
        for s in (self.normal_shifted if using_normal else self.shifted):
            d = np.minimum(d, np.abs(g1 - s))
        vals = d[core]
        if vals.size == 0:
            return DetectResult(False, reason="mask")
        med = float(np.median(vals))
        sigma = 1.4826 * float(np.median(np.abs(vals - med))) + 1e-6
        thr = max(10.0, med + k * sigma) if fixed_threshold is None else float(fixed_threshold)
        if not np.isfinite(thr) or not 0 < thr <= 255:
            raise ValueError("差分阈值必须在 0–255 之间")
        threshold_map = np.maximum(thr, np.minimum(thr+variation_cap, 6+3*self.normal_sigma)) if using_normal else thr
        anom = ((d > threshold_map) & core).astype(np.uint8) * 255
        anom = cv2.morphologyEx(anom, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        anom = cv2.morphologyEx(anom, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
        anom[~core] = 0
        n, lab, st, _ = cv2.connectedComponentsWithStats(anom, 8)
        Minv = np.linalg.inv(M)
        regions = []
        for i in range(1, n):
            x, y, w, h, area = st[i]
            if area < min_area:
                continue
            peak = float(d[lab == i].max())
            if peak < min_peak:
                continue
            pts = np.float32([[x, y], [x + w, y], [x + w, y + h], [x, y + h]]).reshape(-1, 1, 2)
            q = cv2.perspectiveTransform(pts, Minv).reshape(-1, 2)
            bbox = (float(q[:, 0].min()), float(q[:, 1].min()),
                    float(q[:, 0].max()), float(q[:, 1].max()))
            regions.append(Region(bbox=bbox, area=int(area), peak=round(peak, 1),
                                  canon_bbox=(float(x), float(y), float(x+w), float(y+h))))
        regions.sort(key=lambda r: -r.area)
        coverage = cv2.warpPerspective(core.astype(np.uint8)*255, Minv, (bgr.shape[1], bgr.shape[0]),
            flags=cv2.INTER_NEAREST, borderMode=cv2.BORDER_CONSTANT, borderValue=0)
        maximum = float(threshold_map[core].max()) if using_normal else thr
        return DetectResult(True, regions=regions, thr=thr, align_inliers=inl, align_err=err,
            coverage_mask=coverage, threshold_max=maximum, refined=refined,
            normal_groups=len(self.normal_groups) if using_normal else 0)

    def _detect_surface(self, bgr, edge_margin, refine, min_area, min_length, response, tolerance, mask_holes, use_variation, small_response):
        from surface_features import SurfaceReference, inspect
        if not (8 <= min_length <= 200 and .5 <= response <= 30 and 0 <= tolerance <= 8 and 3<=small_response<=100):
            raise ValueError('细线长度、响应或结构容差超出范围')
        prepared, failure = self.prepare_geometry(bgr, int(edge_margin), refine)
        if failure:
            return failure
        canon, M, base_core, inl, err, refined = prepared
        profile=(bool(use_variation),len(self.raw_good_groups))
        if self._surface_ref is None or getattr(self,'_surface_ref_profile',None)!=profile:
            ref = self.raw_tpl if self.raw_tpl is not None else cv2.warpPerspective(
                self.ref_bgr,self.S,(CANON_W,self.canon_h),borderMode=cv2.BORDER_CONSTANT,borderValue=(255,255,255))
            groups=self.raw_good_groups if use_variation and len(self.raw_good_groups)>=3 else []
            self._surface_ref = SurfaceReference(ref,groups)
            self._surface_ref_profile=profile
        model = self._surface_ref
        if (model.green[base_core]>0).mean() < .10:
            return DetectResult(False, reason='surface_profile',align_inliers=inl,align_err=err)
        lines, patches, score, core = inspect(model,canon,base_core,cut=float(response),
            minlen=float(min_length),edge_tolerance=int(tolerance),mask_holes=bool(mask_holes),min_area=int(min_area),small_response=float(small_response))
        if core.sum() < .9*base_core.sum():
            return DetectResult(False,reason='coverage',align_inliers=inl,align_err=err)
        Minv=np.linalg.inv(M)
        regions=[]
        for kind, hits in [('scratch',lines),('material',patches)]:
            for hit in hits:
                actual_kind=hit.get('kind',kind)
                x,y,x1,y1=hit['box']
                pts=np.float32([[x,y],[x1,y],[x1,y1],[x,y1]]).reshape(-1,1,2)
                q=cv2.perspectiveTransform(pts,Minv).reshape(-1,2)
                box=(float(q[:,0].min()),float(q[:,1].min()),float(q[:,0].max()),float(q[:,1].max()))
                peak=float(hit.get('peak',255.0))
                regions.append(Region(box,int(hit['area']),round(peak,2),(float(x),float(y),float(x1),float(y1)),actual_kind,float(hit.get('length',0))))
        # A line-shaped foreign object may activate both channels; keep one box.
        unique=[]
        for r in regions:
            x,y,x1,y1=r.canon_bbox
            duplicate=False
            for prev in unique:
                a,b,a1,b1=prev.canon_bbox
                overlap=max(0,min(x1,a1)-max(x,a))*max(0,min(y1,b1)-max(y,b))
                if overlap>.4*min((x1-x)*(y1-y),(a1-a)*(b1-b)):
                    duplicate=True;break
            if not duplicate:unique.append(r)
        coverage=cv2.warpPerspective(core.astype(np.uint8)*255,Minv,(bgr.shape[1],bgr.shape[0]),flags=cv2.INTER_NEAREST,borderValue=0)
        info=dict(mode='green_surface_v1',holes=len(model.hole_circles) if mask_holes else 0,
            legacy_reference=self.raw_tpl is None,normal_groups=model.normal_groups,
            line_count=sum(r.kind=='scratch' for r in unique),material_count=sum(r.kind=='material' for r in unique),small_count=sum(r.kind=='structure' for r in unique),
            color_policy='green shade and yellow/grey metal variations are not standalone NG evidence',
            structure_tolerance=int(tolerance))
        return DetectResult(True,regions=unique,thr=float(response),threshold_max=float(response),
            align_inliers=inl,align_err=err,coverage_mask=coverage,refined=refined,surface_info=info,normal_groups=model.normal_groups)

    # ---------------- 存取 ----------------
    def save(self, path: Path, label=""):
        path = Path(path)
        meta = {"label": label or self.label, "frames": self.n_frames,
                "enhance": bool(self.enhance), "clip": float(self.clip),
                "canon": [CANON_W, self.canon_h], "consistency": self.consistency,
                "schema": 3, "normal_names": self.normal_names, "raw_template": self.raw_tpl is not None}
        extra = {"raw_tpl": self.raw_tpl} if self.raw_tpl is not None else {}
        if self.raw_good_groups:extra['surface_normal_groups']=np.stack(self.raw_good_groups)
        np.savez_compressed(path,
                            ref_bgr=self.ref_bgr, S=self.S, tpl=self.tpl,
                            mask=self.mask, meta=json.dumps(meta),
                            normal_groups=np.stack(self.normal_groups) if self.normal_groups else np.empty((0, self.canon_h, CANON_W), np.uint8),**extra)
        return path

    @classmethod
    def load(cls, path: Path):
        z = np.load(Path(path), allow_pickle=False)
        tm = cls()
        tm.ref_bgr = z["ref_bgr"]
        tm.ref_gray = cv2.cvtColor(tm.ref_bgr, cv2.COLOR_BGR2GRAY)
        tm.S = z["S"]
        tm.tpl = z["tpl"]
        if "raw_tpl" in z:
            tm.raw_tpl=z["raw_tpl"].copy()
            if tm.raw_tpl.shape!=tm.tpl.shape or tm.raw_tpl.dtype!=np.uint8:
                raise ValueError("原始模板尺寸或格式无效")
        meta = json.loads(str(z["meta"]))
        tm.canon_h = int(meta["canon"][1])
        tm.label = meta.get("label", "")
        tm.enhance = bool(meta.get("enhance", False))
        tm.clip = float(meta.get("clip", 2.5))
        tm.n_frames = int(meta.get("frames", 0))
        tm.consistency = meta.get("consistency")
        tm.mask = z["mask"]
        tm.core = erode_mask(tm.mask, 10) > 0
        g = cv2.cvtColor(tm.tpl, cv2.COLOR_BGR2GRAY).astype(np.float32)
        tm.tpl_gray = cv2.GaussianBlur(g, (0, 0), 2.1)
        tm.shifted = []
        for dy in range(-SHIFT, SHIFT + 1):
            for dx in range(-SHIFT, SHIFT + 1):
                M = np.float32([[1, 0, dx], [0, 1, dy]])
                tm.shifted.append(cv2.warpAffine(tm.tpl_gray, M, (CANON_W, tm.canon_h),
                                                 flags=cv2.INTER_LINEAR,
                                                 borderMode=cv2.BORDER_REPLICATE))
        if 'normal_groups' in z:
            groups = z['normal_groups']
            if groups.ndim != 3 or groups.shape[0] > 12 or groups.shape[1:] != tm.tpl.shape[:2] or groups.dtype != np.uint8:
                raise ValueError('正常样本模型尺寸或数量无效')
            tm.normal_groups = [x.copy() for x in groups]
            tm.normal_names = meta.get('normal_names', [])
        if not tm.normal_groups:
            tm.normal_groups = [np.rint(tm.tpl_gray).astype(np.uint8)]
            tm.normal_names = ['初始良品标定']
        if 'surface_normal_groups' in z:
            groups=z['surface_normal_groups']
            if groups.dtype!=np.uint8 or groups.ndim!=4 or groups.shape[0]>12 or groups.shape[1:]!=tm.tpl.shape:
                raise ValueError('颜色兼容良品模型尺寸或数量无效')
            tm.raw_good_groups=[x.copy() for x in groups]
        if not tm.raw_good_groups:
            tm.raw_good_groups=[(tm.raw_tpl if tm.raw_tpl is not None else cv2.warpPerspective(tm.ref_bgr,tm.S,(CANON_W,tm.canon_h),borderMode=cv2.BORDER_CONSTANT,borderValue=(255,255,255))).copy()]
        tm._refresh_normal()
        z.close()
        return tm
