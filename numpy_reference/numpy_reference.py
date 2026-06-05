import numpy as np
import os

M1 = 0.00036199
M2 = 0.00143881
M3 = 0.01956364
M4 = 1.00000000

"""
Clip 01: [True Label: two]   -> 4c77947d_nohash_0.wav
Clip 02: [True Label: nine]  -> 3ce4910e_nohash_1.wav
Clip 03: [True Label: five]  -> 2927c601_nohash_4.wav
Clip 04: [True Label: four]  -> 563aa4e6_nohash_2.wav
Clip 05: [True Label: eight] -> 3b4f8f24_nohash_1.wav
Clip 06: [True Label: two]   -> cc8b3228_nohash_1.wav
Clip 07: [True Label: nine]  -> f8f60f59_nohash_0.wav
Clip 08: [True Label: three] -> 94d370bf_nohash_0.wav
Clip 09: [True Label: seven] -> c93d5e22_nohash_4.wav
Clip 10: [True Label: nine]  -> 4f256313_nohash_0.wav
Clip 11: [True Label: five]  -> e9287461_nohash_0.wav
Clip 12: [True Label: eight] -> a04817c2_nohash_4.wav
Clip 13: [True Label: four]  -> c4e00ee9_nohash_3.wav
Clip 14: [True Label: two]   -> 559bc36a_nohash_2.wav
Clip 15: [True Label: six]   -> 0a7c2a8d_nohash_2.wav
Clip 16: [True Label: nine]  -> ad89eb1e_nohash_0.wav
"""

CLASSES = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]

def load_raw_binary(filepath, shape):
    if not os.path.exists(filepath):
        raise FileNotFoundError(f"Cannot find {filepath}")
    return np.fromfile(filepath, dtype=np.int8).reshape(shape)

if __name__ == "__main__":
    X_int8 = load_raw_binary("./weights/input_spectrogram.bin", (16, 768))
    W1_int8 = load_raw_binary("./weights/layer1_weights.bin", (128, 768))
    W2_int8 = load_raw_binary("./weights/layer2_weights.bin", (128, 128))
    W3_int8 = load_raw_binary("./weights/layer3_weights.bin", (128, 128))
    W4_int8 = load_raw_binary("./weights/layer4_weights.bin", (16, 128))

    print("Data loaded. Executing Static Hardware Pipeline...\n")

    # =====================================================================
    # LAYER 1
    # =====================================================================
    Y1_int32 = np.dot(X_int8.astype(np.int32), W1_int8.T.astype(np.int32))
    Y1_int32 = np.maximum(0, Y1_int32) # Hardware ReLU
    
    # Static Requantization with Saturation Clipping
    X2_int8 = np.clip(np.round(Y1_int32 * M1), 0, 127).astype(np.int8)

    # =====================================================================
    # LAYER 2
    # =====================================================================
    Y2_int32 = np.dot(X2_int8.astype(np.int32), W2_int8.T.astype(np.int32))
    Y2_int32 = np.maximum(0, Y2_int32) 
    X3_int8 = np.clip(np.round(Y2_int32 * M2), 0, 127).astype(np.int8)

    # =====================================================================
    # LAYER 3
    # =====================================================================
    Y3_int32 = np.dot(X3_int8.astype(np.int32), W3_int8.T.astype(np.int32))
    Y3_int32 = np.maximum(0, Y3_int32) 
    X4_int8 = np.clip(np.round(Y3_int32 * M3), 0, 127).astype(np.int8)

    # =====================================================================
    # LAYER 4 (OUTPUT)
    # =====================================================================
    Y4_int32 = np.dot(X4_int8.astype(np.int32), W4_int8.T.astype(np.int32))
    Y4_int32 = np.maximum(0, Y4_int32) 
    X5_int8 = np.clip(np.round(Y4_int32 * M4), 0, 127).astype(np.int8)

    # print the final output
    np.set_printoptions(threshold=np.inf)
    print(X5_int8)
    
    # print the prediction results
    print("--- Final Batch Predictions ---")
    valid_logits = X5_int8[:, :9] 
    predictions = np.argmax(valid_logits, axis=1)
    
    for i, pred_idx in enumerate(predictions):
        predicted_word = CLASSES[pred_idx]
        print(f"Audio Clip {i+1:02d}: Predicted = '{predicted_word}' (Class ID: {pred_idx})")