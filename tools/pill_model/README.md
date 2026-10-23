# Pill Model Training

This folder contains a small training pipeline for generating the pill
classification model used by MedSafe.

## Dataset Layout

Place labeled pill images under a `data/` directory like this:

```text
data/
  class_a/
    image1.jpg
    image2.jpg
  class_b/
    image3.jpg
    image4.jpg
```

Each subfolder name becomes a class label.

If you only have one image per pill and want to keep everything in one folder,
you can put the images directly in `data/` and name each file after the pill.
The script will treat each filename stem as the label, create temporary class
folders automatically, and re-encode images to PNG so TensorFlow can read them.

## Train And Export

Install the Python dependencies:

```bash
python3 -m pip install -r tools/pill_model/requirements.txt
```

Then train and export the model:

```bash
python3 tools/pill_model/train_pill_model.py --data-dir data --output-dir artifacts
```

If your images are flat in `tools/pill_model/data/`, make sure the filenames
are the pill labels, for example `metformin.jpg`, `ibuprofen.jpg`, and so on.
Mixed formats are fine as long as Pillow can open them; the script will convert
AVIF, WebP, JPEG, and PNG inputs into PNG for training.

The script writes these files:

- `artifacts/pill_classifier.tflite`
- `artifacts/pill_labels.txt`
- `artifacts/pill_classifier_saved_model/`

Copy the `.tflite` file and labels into `assets/models/` so the Flutter app
can load them.