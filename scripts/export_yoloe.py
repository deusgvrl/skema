"""Export the YOLOE text-prompt model the app ships (A10-60).

Prompts are fixed in the Core ML file. Each prompt is a class; its name is the label the app sees.
Several prompts share one label: the 20 light prompts are all "studio lighting" and the 3 camera prompts
are all "Camera". The app compares labels after trimming spaces and ignoring case.

Usage (needs ultralytics, coremltools, the yoloe-26m-seg.pt weights and the mobileclip2_b.ts text encoder
in the current folder, as in the YOLOE PoC's models/ folder):

    python export_yoloe.py
    # then copy yoloe-26m-seg.mlpackage into "Final Challenge App/Resources/Models/"

Tested with Ultralytics 8.4.201, coremltools 9.0, Python 3.13 on 10 Nov 2026.
"""

from ultralytics import YOLOE

WEIGHTS = "yoloe-26m-seg.pt"

# The 20 light prompts of the YOLOE PoC (poc/lidar-yoloe-measure/models/export_yoloe.py, 10 Nov 2026).
LIGHT_LABEL = "studio lighting"
LIGHT_PROMPTS = [
    "studio lighting", "studio light", "photography lighting equipment",
    "softbox", "octagonal softbox", "square softbox", "strip softbox",
    "umbrella light", "photography umbrella",
    "ring light", "beauty dish",
    "studio strobe", "monolight", "studio flash", "speedlight", "camera flash",
    "LED panel light", "LED video light", "snoot", "light stand",
]

# Chosen by Amadeus, 10 Nov 2026.
CAMERA_LABEL = "Camera"
CAMERA_PROMPTS = ["Camera", "DSLR Camera", "Mirrorless Camera"]


def main() -> None:
    model = YOLOE(WEIGHTS)
    prompts = LIGHT_PROMPTS + CAMERA_PROMPTS
    names = [LIGHT_LABEL] * len(LIGHT_PROMPTS) + [CAMERA_LABEL] * len(CAMERA_PROMPTS)
    embeddings = model.model.get_text_pe(prompts).detach()
    model.set_classes(names, embeddings)
    print("classes:", model.names)
    model.export(format="coreml", imgsz=640, nms=False)


if __name__ == "__main__":
    main()
