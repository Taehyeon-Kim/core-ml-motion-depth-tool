# video-depth

영상 파일을 프레임별 depth 영상으로 변환하는 macOS CLI입니다. 밝을수록 카메라에 가깝습니다. 영상은 로컬에서 처리하며 첫 실행 때 모델만 내려받습니다.

## 설치

Apple Silicon Mac, Xcode Command Line Tools(`swiftc`), `ffmpeg`와 `ffprobe`, Python 3와 NumPy가 필요합니다. 예: `xcode-select --install`, `brew install ffmpeg python numpy`.

## 사용법

```sh
./video-depth input.mp4 output.mp4
```

출력은 원본의 프레임 수와 길이를 유지하는 무음 H.264 회색조 영상입니다. 모델과 컴파일 결과는 `~/Library/Caches/video-depth`에 저장합니다. 캐시 위치는 `VIDEO_DEPTH_CACHE` 환경 변수로 바꿀 수 있습니다.

모델: [Apple Core ML Depth Anything V2 Small](https://huggingface.co/apple/coreml-depth-anything-v2-small), 리비전 `cfef6f6f2a70783dedc0bfae40cecbc2052285d3`, 라이선스 **Apache-2.0**. 다운로드 파일의 SHA-256을 확인합니다.

## 알려진 한계

- macOS/Apple Silicon 전용입니다. 깊이는 상대적인 밝기이며 실제 거리 단위가 아닙니다.
- 작은 물건과 미세한 얼굴 표정은 약하게 표현될 수 있습니다. 화면에 합성된 글자나 도형은 평평한 형태로 남을 수 있습니다.
- 장면 전환을 따로 처리하지 않습니다. 밝기 범위가 약 1초에 걸쳐 서서히 따라가므로, 전환 직후 몇 프레임은 일부가 너무 밝거나 어둡게 잘리고 1초 안팎의 짧은 장면은 대비가 낮게 보일 수 있습니다. 내용이 없는 단색 화면에서는 의미 없는 그라데이션이 나옵니다.
- 가변 프레임레이트 영상은 프레임 수와 전체 길이를 맞추지만 개별 프레임의 시간 간격은 보존하지 않습니다.
- H.264 `yuv420p`는 짝수 크기가 필요하므로 홀수 가로·세로 크기는 각 축을 최대 1픽셀 늘립니다.
