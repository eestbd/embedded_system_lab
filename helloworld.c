/******************************************************************************
*
* Copyright (C) 2009 - 2014 Xilinx, Inc.  All rights reserved.
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* Use of the Software is limited solely to applications:
* (a) running on a Xilinx device, or
* (b) that interact with a Xilinx device through a bus or interconnect.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
* XILINX  BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
* WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF
* OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*
* Except as contained in this notice, the name of the Xilinx shall not be used
* in advertising or otherwise to promote the sale, use or other dealings in
* this Software without prior written authorization from Xilinx.
*
******************************************************************************/

/*
 * helloworld.c: simple test application
 *
 * This application configures UART 16550 to baud rate 9600.
 * PS7 UART (Zynq) is not initialized by this application, since
 * bootrom/bsp configures it to baud rate 115200
 *
 * ------------------------------------------------
 * | UART TYPE   BAUD RATE                        |
 * ------------------------------------------------
 *   uartns550   9600
 *   uartlite    Configurable only in HW design
 *   ps7_uart    115200 (configured by bootrom/bsp)
 */

#include <stdio.h>
#include <stdlib.h>
#include "platform.h"
#include "xil_printf.h"

#include "xparameters.h"
#include "xil_io.h"
#include "sleep.h"
#include "xscugic.h"
#include "xil_exception.h"
#include "xil_cache.h"
#include "xil_types.h"

#define INTC_DEVICE_ID      XPAR_SCUGIC_0_DEVICE_ID
#define INTC_DEVICE_INT_ID  61 // ID 61

#define OUTPUT_BRAM_OFFSET  0x28800  // Byte offset from PL base address to the 16x16 result matrix
#define NUM_CLIPS           16       // Number of audio clips (rows in output matrix)
#define NUM_CLASSES         9        // Number of valid output classes (columns 0..8)
#define OUTPUT_COLS         16       // Total columns in the output matrix

int SetUpInterruptSystem(XScuGic *XScuGicInstancePtr);
void DeviceDriverHandler(void *CallbackRef);

XScuGic InterruptController;
static XScuGic_Config *GicConfig;

volatile static int InterruptProcessed = FALSE;

static const char *CLASSES[NUM_CLASSES] = {
    "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"
};

static void AssertPrint(const char8 *FilenamePtr, s32 LineNumber){
    xil_printf("ASSERT: File Name: %s ", FilenamePtr);
    xil_printf("Line Number: %d\r\n", LineNumber);
}


int main()
{
    init_platform();

    int Status;
    Xil_AssertSetCallback(AssertPrint);

    GicConfig = XScuGic_LookupConfig(INTC_DEVICE_ID);
    if (NULL == GicConfig) {
        return XST_FAILURE;
    }

    Status = XScuGic_CfgInitialize(&InterruptController, GicConfig,
                    GicConfig->CpuBaseAddress);
    if (Status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    // Self-test
    Status = XScuGic_SelfTest(&InterruptController);
    if (Status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    // IRQ setup
    Status = SetUpInterruptSystem(&InterruptController);
    if (Status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    Status = XScuGic_Connect(&InterruptController, INTC_DEVICE_INT_ID,
                   (Xil_ExceptionHandler)DeviceDriverHandler,
                   (void *)&InterruptController);

    if (Status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    // Enable the interrupt for the device
    XScuGic_SetPriorityTriggerType(&InterruptController, INTC_DEVICE_INT_ID, 0x00, 0x3);
    XScuGic_Enable(&InterruptController, INTC_DEVICE_INT_ID);

    while (1) {
        if (InterruptProcessed) {
            InterruptProcessed = FALSE;

            // ------------------------------------------------------------------
            // Step 1: Read the 16x16 int8 result matrix from PL BRAM.
            //
            // The matrix is stored row-major at BASEADDR + OUTPUT_BRAM_OFFSET.
            // Each Xil_In32 call returns one 32-bit word containing four packed
            // int8 values in little-endian byte order (byte 0 = bits [7:0], etc.).
            // Total reads: 16 rows * 16 cols / 4 bytes-per-word = 64 words.
            // ------------------------------------------------------------------
            int8_t output[NUM_CLIPS][OUTPUT_COLS];
            u32 base = XPAR_FINALPRJ_WRAPPER_0_BASEADDR + OUTPUT_BRAM_OFFSET;
            int elem = 0;

            for (int word_idx = 0; word_idx < (NUM_CLIPS * OUTPUT_COLS / 4); word_idx++) {
                u32 raw = Xil_In32(base + (word_idx * 4));

                // Unpack four packed int8 values (little-endian) into the row-major output array
                output[elem / OUTPUT_COLS][elem % OUTPUT_COLS] = (int8_t)( raw        & 0xFF); elem++;
                output[elem / OUTPUT_COLS][elem % OUTPUT_COLS] = (int8_t)((raw >>  8) & 0xFF); elem++;
                output[elem / OUTPUT_COLS][elem % OUTPUT_COLS] = (int8_t)((raw >> 16) & 0xFF); elem++;
                output[elem / OUTPUT_COLS][elem % OUTPUT_COLS] = (int8_t)((raw >> 24) & 0xFF); elem++;
            }

            // ------------------------------------------------------------------
            // Step 2: For each audio clip (row), find the class (column 0..8)
            //         with the highest score - equivalent to:
            //             valid_logits = X5_int8[:, :9]
            //             predictions  = np.argmax(valid_logits, axis=1)
            // ------------------------------------------------------------------
            xil_printf("--- Final Batch Predictions ---\r\n");

            for (int clip = 0; clip < NUM_CLIPS; clip++) {
                int8_t max_val  = output[clip][0];
                int    pred_idx = 0;

                for (int c = 1; c < NUM_CLASSES; c++) {
                    if (output[clip][c] > max_val) {
                        max_val  = output[clip][c];
                        pred_idx = c;
                    }
                }

                xil_printf("Audio Clip %02d: Predicted = '%s' (Class ID: %d)\r\n",
                           clip + 1, CLASSES[pred_idx], pred_idx);
            }

            // Re-enable interrupt
            XScuGic_Enable(&InterruptController, INTC_DEVICE_INT_ID);
        }
    }

    cleanup_platform();
    return 0;
}



int SetUpInterruptSystem(XScuGic *XScuGicInstancePtr) {
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
            (Xil_ExceptionHandler) XScuGic_InterruptHandler,
            XScuGicInstancePtr);
    Xil_ExceptionEnable();
    return XST_SUCCESS;
}

void DeviceDriverHandler(void *CallbackRef) {
    XScuGic_Disable(&InterruptController, INTC_DEVICE_INT_ID);
    InterruptProcessed = TRUE;
}
