import os
import pandas as pd
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw
import matplotlib.pyplot as plt

def parse_voc_annotations(annotations_dir):
    """Parse VOC XML annotation files with robust coordinate handling."""
    
    annotations = []
    
    for xml_file in os.listdir(annotations_dir):
        if xml_file.endswith('.xml'):
            xml_path = os.path.join(annotations_dir, xml_file)
            tree = ET.parse(xml_path)
            root = tree.getroot()
            
            # Extract basic info
            filename = root.find('filename').text
            size = root.find('size')
            width = int(size.find('width').text)
            height = int(size.find('height').text)
            
            # Extract object annotations
            for obj in root.findall('object'):
                class_name = obj.find('name').text
                bbox = obj.find('bndbox')
                
                # CRITICAL FIX: Handle floating-point coordinates
                xmin = int(float(bbox.find('xmin').text))
                ymin = int(float(bbox.find('ymin').text))
                xmax = int(float(bbox.find('xmax').text))
                ymax = int(float(bbox.find('ymax').text))
                
                annotations.append({
                    'filename': filename,
                    'width': width,
                    'height': height,
                    'class': class_name,
                    'xmin': xmin,
                    'ymin': ymin,
                    'xmax': xmax,
                    'ymax': ymax
                })
    
    return pd.DataFrame(annotations)

def visualize_image(image_path, annotations, filename):
    """Visualize an image with its bounding box annotations."""
    
    # Filter annotations for this image
    img_annotations = annotations[annotations['filename'] == filename]
    
    if img_annotations.empty:
        print(f"No annotations found for {filename}")
        return
        
    # Load and display image
    image = Image.open(image_path)
    draw = ImageDraw.Draw(image)
    
    # Draw bounding boxes
    for _, ann in img_annotations.iterrows():
        bbox = [ann['xmin'], ann['ymin'], ann['xmax'], ann['ymax']]
        draw.rectangle(bbox, outline='red', width=2)
        draw.text((ann['xmin'], ann['ymin'] - 10), ann['class'], fill='red')
    
    # Display using matplotlib for Jupyter compatibility
    plt.figure(figsize=(12, 8))
    plt.imshow(image)
    plt.axis('off')
    plt.title(f'Image: {filename}')
    plt.show()

if __name__ == "__main__":
    # CORRECT PATH FOR REMOTE SERVER E4S CONTAINER
    voc_path = '/opt/hccs_shared/Share/VOC2012_train_val/VOC2012_train_val'
    annotations_dir = os.path.join(voc_path, 'Annotations')
    images_dir = os.path.join(voc_path, 'JPEGImages')
    
    print(f"VOC Dataset Path: {voc_path}")
    print(f"Annotations: {annotations_dir}")
    print(f"Images: {images_dir}")
    
    # Verify paths exist
    if not os.path.exists(annotations_dir):
        print(f"❌ Annotations directory not found: {annotations_dir}")
        print("Make sure you're running this inside the E4S Singularity container")
        exit(1)
    
    if not os.path.exists(images_dir):
        print(f"❌ Images directory not found: {images_dir}")
        exit(1)
        
    print("✅ Paths validated successfully!")
    
    # Parse all annotations
    print("\nLoading VOC annotations...")
    df = parse_voc_annotations(annotations_dir)
    
    print(f"\n✅ Dataset loaded successfully!")
    print(f"Total annotations: {len(df)}")
    print(f"Unique images: {df['filename'].nunique()}")
    print(f"Unique classes: {df['class'].nunique()}")
    
    # Show class distribution
    print("\nClass distribution:")
    print(df['class'].value_counts())
    
    # Example visualization
    sample_filename = df['filename'].iloc[0]
    sample_image_path = os.path.join(images_dir, sample_filename)
    
    if os.path.exists(sample_image_path):
        print(f"\nVisualizing sample image: {sample_filename}")
        visualize_image(sample_image_path, df, sample_filename)
    else:
        print(f"\nImage file not found: {sample_image_path}")
