# qwen-vl-rk3588

Qwen2.5-VL-3B 在 RK3588 上的离线部署。输入一张图片和一句问题，模型在板子的 NPU 上直接推理出答案，全程不联网。

## 能做什么

给一张图，用 `<image>` 开头提问，模型会读出图里的内容并回答。跑起来是这样：

```
User: <image>
      描述一下这张图片
AI  : 图中是一轮满月，悬挂在夜空中……
```

板端实际运行（测试图 `images/Moon.jpg`）：

![运行效果](images/demo.png)

## 结构

```
图片 → 视觉编码器（ViT，RKNN/FP16）→ 语言模型（RKLLM/W8A8）→ 文本
                全部在 RK3588 NPU 上执行
```

Qwen2.5-VL-3B 拆成两段处理：视觉部分用 FP16 转成 RKNN 格式，语言部分做 W8A8 量化后交给 RKLLM 运行时。视觉编码器保留 FP16 是因为它对精度更敏感，一并压到 8bit 掉点明显。

推理核心用 C++17 写成一个类，主程序只负责读图、组 prompt、打印结果。

## 编译

需要的东西：

- RK3588 开发板，Buildroot 系统
- `aarch64-linux-gnu-g++`
- rknpu 驱动和 rkllm-runtime

用 CMake 和随仓库提供的 toolchain 文件：

```bash
JOBS=8 ./build.sh
```

也可以手工编：

```bash
aarch64-linux-gnu-g++ -std=c++17 -O3 \\
  -I include -I /usr/include/opencv4 \\
  src/main.cpp src/RK35llm.cpp \\
  ./lib/libopencv_core.so ./lib/libopencv_imgcodecs.so ./lib/libopencv_imgproc.so \\
  ./lib/libpng16.so.16 ./lib/libz.so.1 \\
  ./lib/librknnrt.so ./lib/librkllmrt.so \\
  ./lib/libgomp.so.1 \\
  -ldl -lpthread \\
  -o VLM_NPU_stb
aarch64-linux-gnu-strip VLM_NPU_stb
```

## 运行

模型文件约 4.9GB，没进仓库，下载地址见 `docs/`。放到板子上之后：

```bash
./run_board.sh                  # 用仓库里的测试图
./run_board.sh /root/xxx.jpg    # 用指定图片
```

## 部署时遇到的问题

| 现象 | 原因 | 处理 |
|---|---|---|
| `rkllm init` 卡住不返回 | 从 NFS 读大文件进了内核不可中断等待 | 模型改放板子本地 |
| 传模型时 Connection reset | 板子网络大流量下不稳 | 拆成 200MB 分块传再合并 |
| `cvtColor` 报 `!_src.empty()` | 板端 OpenCV 编译时没带 libjpeg | 换成 header-only 的 stb_image 读图 |
| `invalid rkllm model` | 之前下载中断，文件不完整 | 重新下载并核对文件大小 |
| 加载共享库失败 | `LD_LIBRARY_PATH` 里运行时库排在系统库后面 | 把运行时库目录提到最前 |

## 目录

```
qwen-vl-rk3588/
├── CMakeLists.txt
├── build.sh              # 交叉编译
├── run_board.sh          # 板端启动
├── src/                  # main.cpp / RK35llm.cpp / capture.cpp
├── include/
├── lib/                  # 板端运行时 .so
├── 3rdparty/             # stb_image 等
├── images/               # 测试图
└── docs/                 # 开发笔记、模型下载说明
```

`lib/` 里的 `.so` 都是从板端 Buildroot rootfs 提取的 aarch64 运行时库：`librknnrt.so` / `librkllmrt.so` 是 Rockchip 的 NPU 运行时（rknpu 0.9.8），OpenCV / png / zlib 是板端自带的系统库，`libgomp.so.1` 是板端缺失、单独补上的 OpenMP 库。

## License

MIT
