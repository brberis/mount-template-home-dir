# Import necessary libraries
import os
import pandas as pd
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------------------
# 1. DEFINE PATHS FOR JUPYTER NOTEBOOK (using SharedContent symbolic link)
# ---------------------------------------------------------------------------
# IMPORTANT: Use SharedContent path for Jupyter notebook environment
# This path works through the symbolic link that Jupyter can access
shared_folder_path = '/home/hccsadmin1/SharedContent/LocalShare/VOC2012_train_val'

# Define the standard path to the Pascal VOC 2012 dataset root
voc_root = os.path.join(shared_folder_path, 'VOC2012_train_val')
annotations_dir = os.path.join(voc_root, 'Annotations')
images_dir = os.path.join(voc_root, 'JPEGImages')

print(f"Using dataset path: {voc_root}")
print(f"Annotations directory: {annotations_dir}")
print(f"Images directory: {images_dir}")

# ---------------------------------------------------------------------------
# 2. PARSE XML ANNOTATIONS AND CREATE A DATAFRAME
# ---------------------------------------------------------------------------
def parse_voc_annotations(annotations_dir):
    """Parses all XML files in the Annotations directory."""
    xml_data = []
    # Loop through every annotation file
    for xml_file in os.listdir(annotations_dir):
        if not xml_file.endswith('.xml'):
            continue
        
        tree = ET.parse(os.path.join(annotations_dir, xml_file))
        root = tree.getroot()
        
        image_name = root.find('filename').text
        
        # Find every object in the image
        for obj in root.findall('object'):
            label = obj.find('name').text
            bbox = obj.find('bndbox')
            # Get bounding box coordinates (handle float values properly)
            xmin = int(float(bbox.find('xmin').text))
            ymin = int(float(bbox.find('ymin').text))
            xmax = int(float(bbox.find('xmax').text))
            ymax = int(float(bbox.find('ymax').text))
            
            xml_data.append({
                'image_name': image_name,
                'label': label,
                'xmin': xmin,
                'ymin': ymin,
                'xmax': xmax,
                'ymax': ymax
            })
    return pd.DataFrame(xml_data)

# Check if directory exists and parse annotations
if not os.path.exists(annotations_dir):
    print(f"ERROR: Directory not found at '{annotations_dir}'.")
    print("Please check that the SharedContent symbolic link is working properly.")
else:
    print(f"\nParsing annotations from: {annotations_dir}")
    # Create the DataFrame
    voc_df = parse_voc_annotations(annotations_dir)
    print(f"Successfully parsed {len(voc_df)} annotations from {voc_df['image_name'].nunique()} images.")
    print("\nHere are the first 5 entries in the DataFrame:")
    
    # Use display in Jupyter, print otherwise
    try:
        display(voc_df.head())
    except NameError:
        print(voc_df.head())

print("-" * 70)

# ---------------------------------------------------------------------------
# 3. VISUALIZE A SAMPLE IMAGE WITH ITS BOUNDING BOXES
# ---------------------------------------------------------------------------
def visualize_image(image_name, dataframe):
    """Draws bounding boxes on a given image."""
    # Get the full path to the image
    img_path = os.path.join(images_dir, image_name)
    
    if not os.path.exists(img_path):
        print(f"Image not found: {img_path}")
        return
    
    # Open the image
    img = Image.open(img_path).convert("RGB")
    draw = ImageDraw.Draw(img)
    
    # Get all annotations for this specific image
    image_annotations = dataframe[dataframe['image_name'] == image_name]
    
    # Draw a rectangle and label for each object
    for _, row in image_annotations.iterrows():
        box = [row['xmin'], row['ymin'], row['xmax'], row['ymax']]
        draw.rectangle(box, outline="red", width=3)
        
        # Add text label (adjust position to avoid overlap)
        label_text = row['label']
        draw.text((row['xmin'], max(0, row['ymin']-20)), label_text, fill="red")

    print(f"Displaying image '{image_name}' with {len(image_annotations)} bounding boxes:")
    
    # Use display in Jupyter, show info otherwise
    try:
        display(img)
    except NameError:
        print(f"Image size: {img.size}, Mode: {img.mode}")
        print("Note: Run this in Jupyter notebook to see the actual image.")

# Visualize a random image from the dataset
if 'voc_df' in locals() and not voc_df.empty:
    sample_image = voc_df['image_name'].sample(1).iloc[0]
    visualize_image(sample_image, voc_df)
    
    # Show dataset statistics
    print(f"\nDataset Statistics:")
    print(f"Total annotations: {len(voc_df):,}")
    print(f"Unique images: {voc_df['image_name'].nunique():,}")
    print(f"Average annotations per image: {len(voc_df)/voc_df['image_name'].nunique():.1f}")
    
    print(f"\nTop 10 object classes:")
    class_counts = voc_df['label'].value_counts().head(10)
    for class_name, count in class_counts.items():
        print(f"  {class_name:12}: {count:5,} annotations")
