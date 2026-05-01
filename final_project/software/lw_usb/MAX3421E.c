/* MAX3421E low-level functions                             */
/* reading, writing registers, reset, host transfer, etc.   */
/* GPIN, GPOUT are as per tutorial, reassign if necessary   */
/* USB power on is GPOUT7, USB power overload is GPIN7      */

#define _MAX3421E_C_

#include "stdlib.h"
#include "stdio.h"
#include "string.h"
#include "project_config.h"
#include "xparameters.h"
#include <unistd.h>
#include <xspi.h>
#include <xgpio.h>
#include <xtmrctr.h>
#include "xintc.h"

/* variables and data structures */

/* External variables */

extern BYTE usb_task_state;
static XSpi SpiInstance;
static int Status;
static XGpio Gpio_rst;
static XGpio Gpio_int;
static XSpi_Config *ConfigPtr;	/* Pointer to Configuration data */
XTmrCtr Usb_timer;
static const u32 kUsbSpiSlaveMask = 0x01;
static BYTE max3421_spi_ok = 0;

static void max_spi_select(int select_slave) {
	int sel_status;
	if (select_slave) {
		sel_status = XSpi_SetSlaveSelect(&SpiInstance, kUsbSpiSlaveMask);
	} else {
		sel_status = XSpi_SetSlaveSelect(&SpiInstance, 0x0);
	}
	if (sel_status != XST_SUCCESS) {
		xil_printf("XSpi_SetSlaveSelect failed: %d (select=%d)\n", sel_status, select_slave);
	}
}

//Initialization of SPI port is already done for you
void SPI_init() {

	xil_printf("Initializing SPI\n");

	ConfigPtr = XSpi_LookupConfig(XPAR_SPI_0_DEVICE_ID);
	if (ConfigPtr == NULL) {
		xil_printf("XSpi_LookupConfig failed for XPAR_SPI_USB_DEVICE_ID\n");
		return;
	}

	Status = XSpi_CfgInitialize(&SpiInstance, ConfigPtr,
				  ConfigPtr->BaseAddress);
	if (Status != XST_SUCCESS) {
		xil_printf("XSpi_CfgInitialize failed: %d\n", Status);
		return;
	}

	if (Status != XST_SUCCESS)
	{
		xil_printf ("SPI device failed to initialize %d", Status);
	}
	Status = XSpi_SetOptions(&SpiInstance, XSP_MASTER_OPTION | XSP_MANUAL_SSELECT_OPTION);
	if (Status != XST_SUCCESS)
	{
		xil_printf ("SPI device failed to go into master mode %d", Status);
	}

	XSpi_Start(&SpiInstance);
	XSpi_IntrGlobalDisable(&SpiInstance);
}

BYTE SPI_wr(BYTE data) {
	return 0; //This function is not needed
}


/* Functions    */
/* Single host register write   */
void MAXreg_wr(BYTE reg, BYTE val) {
	int retval;

	BYTE send_buf[2] = {reg | 0x02, val}; // DIR bit sets write transaction
	BYTE recv_buf[2];

	//psuedocode:
	//select MAX3421E 
	max_spi_select(1);

	//write reg + 2 via SPI
	//write val via SPI
	//read return code from SPI peripheral (see Xilinx examples) 
	retval = XSpi_Transfer(&SpiInstance, send_buf, recv_buf, 2);

	//if return code != 0 print an error
	if (retval != 0) {
		xil_printf("XSpi_Transfer write error: %d\n", retval);
	}

	//deselect MAX3421E (may not be necessary if you are using SPI peripheral)
	max_spi_select(0);
}


/* multiple-byte write */
/* returns a pointer to a memory position after last written */
BYTE* MAXbytes_wr(BYTE reg, BYTE nbytes, BYTE* data) {
	int retval;

	BYTE send_buf[nbytes + 1];
	BYTE recv_buf[nbytes + 1];

	send_buf[0] = reg | 0x02; // DIR bit sets write transaction
	memcpy(send_buf + 1, data, nbytes);

	//psuedocode:
	//select MAX3421E (may not be necessary if you are using SPI peripheral)
	max_spi_select(1);

	//write reg + 2 via SPI
	//write data[n] via SPI, where n goes from 0 to nbytes-1
	//read return code from SPI peripheral 
	retval = XSpi_Transfer(&SpiInstance, send_buf, recv_buf, nbytes + 1);

	//if return code != 0 print an error
	if (retval != 0) {
		xil_printf("XSpi_Transfer write multiple error: %d\n", retval);
	}

	//deselect MAX3421E (may not be necessary if you are using SPI peripheral)
	max_spi_select(0);

	return (data + nbytes);
}

/* Single host register read        */
BYTE MAXreg_rd(BYTE reg) {
	int retval;

	BYTE send_buf[2] = {reg, 0x00};
	BYTE recv_buf[2];

	//psuedocode:
	//select MAX3421E (
	max_spi_select(1);

	//write reg via SPI
	//read val via SPI
	//read return code from SPI peripheral 
	retval = XSpi_Transfer(&SpiInstance, send_buf, recv_buf, 2);

	//if return code != 0 print an error
	if (retval != 0) {
		xil_printf("XSpi_Transfer read error: %d\n", retval);
	}

	//deselect MAX3421E (may not be necessary if you are using SPI peripheral)
	max_spi_select(0);

	return recv_buf[1]; // data bytes follows command byte
}



/* multiple-bytes register read                             */
/* returns a pointer to a memory position after last read   */
BYTE* MAXbytes_rd(BYTE reg, BYTE nbytes, BYTE* data) {
	int retval;

	BYTE send_buf[nbytes + 1];
	BYTE recv_buf[nbytes + 1];

	memset(send_buf, 0, nbytes + 1);
	send_buf[0] = reg;

	//psuedocode:
	//select MAX3421E (may not be necessary if you are using SPI peripheral)
	max_spi_select(1);

	//write reg via SPI
	//read data[n] from SPI, where n goes from 0 to nbytes-1
	//read return code from SPI peripheral 
	retval = XSpi_Transfer(&SpiInstance, send_buf, recv_buf, nbytes + 1);

	//if return code != 0 print an error
	if (retval != 0) {
		xil_printf("XSpi_Transfer read multiple error: %d\n", retval);
	}

	//deselect MAX3421E (may not be necessary if you are using SPI peripheral)
	max_spi_select(0);

	memcpy(data, recv_buf + 1, nbytes);
	return (data + nbytes);
}
/* reset MAX3421E using chip reset bit. SPI configuration is not affected   */
void MAX3421E_reset(void) {
	Status = XGpio_Initialize(&Gpio_rst, XPAR_GPIO_USB_RST_DEVICE_ID);
	XGpio_SetDataDirection(&Gpio_rst, 1, 0); //configure reset, and set reset to output
	Status = XGpio_Initialize(&Gpio_int, XPAR_GPIO_USB_INT_DEVICE_ID);
	XGpio_SetDataDirection(&Gpio_int, 1, 0x1); //configure int channel bit 0 as input


	//hardware reset, then software reset
	XGpio_DiscreteClear(&Gpio_rst, 1, 0x1);
	xil_printf ("Holding USB in Reset\n");
	for (int delay = 0; delay < 0x7FFFF; delay ++){}
	XGpio_DiscreteSet(&Gpio_rst, 1, 0x1);
	BYTE rev_samples[4];
	xil_printf("MAX3421E revision reads: ");
	for (int i = 0; i < 4; i++) {
		rev_samples[i] = MAXreg_rd(rREVISION);
		xil_printf("%x ", rev_samples[i]);
	}
	xil_printf("\n");
	if ((rev_samples[0] == 0x00 && rev_samples[1] == 0x00 && rev_samples[2] == 0x00 && rev_samples[3] == 0x00) ||
		(rev_samples[0] == 0xFF && rev_samples[1] == 0xFF && rev_samples[2] == 0xFF && rev_samples[3] == 0xFF)) {
		xil_printf("SPI diagnostic: constant revision reads indicate MISO/SS/SCLK wiring or SPI mode issue.\n");
	}
	BYTE tmp = 0;
	BYTE usbirq;

	MAXreg_wr( rUSBCTL, bmCHIPRES);      //Chip (soft) reset. This stops the oscillator
	MAXreg_wr( rUSBCTL, 0x00);           //Remove the reset

	xil_printf("Waiting for PLL to stabilize: ");
	while (!((usbirq = MAXreg_rd(rUSBIRQ)) & bmOSCOKIRQ)) { //wait until the PLL stabilizes
		tmp++;                                      //timeout after 256 attempts
		xil_printf(". (USBIRQ=%x)\n", usbirq);
		if (tmp == 0) {
			xil_printf("reset timeout!, SPI link likely failing. Check MAX3421E SPI wiring/IP config.\n");
			max3421_spi_ok = 0;
			break;
		}
	}
	if ((tmp != 0) && (usbirq & bmOSCOKIRQ)) {
		max3421_spi_ok = 1;
	}
}
/* turn USB power on/off                                                */
/* ON pin of VBUS switch (MAX4793 or similar) is connected to GPOUT0    */
/* OVERLOAD pin of Vbus switch is connected to GPIN7                    */
/* OVERLOAD state low. NO OVERLOAD or VBUS OFF state high.              */
BOOL Vbus_power(BOOL action) {
    BYTE io1 = MAXreg_rd(rIOPINS1);
    BYTE io2 = MAXreg_rd(rIOPINS2);

    // Different lab revisions wire VBUS enable to different MAX3421E GPOUT pins.
    // Drive both common mappings so bring-up does not depend on board revision.
    if (action) {
        io1 |= bmGPOUT0; // legacy mapping
        io2 |= bmGPOUT7; // common ECE385 mapping
    } else {
        io1 &= ~bmGPOUT0;
        io2 &= ~bmGPOUT7;
    }

    MAXreg_wr(rIOPINS1, io1);
    MAXreg_wr(rIOPINS2, io2);
    for (int delay = 0; delay < 0xFFFFF; delay++) {}

    xil_printf("VBUS %s: IOPINS1=%x IOPINS2=%x\n",
            action ? "ON" : "OFF",
            MAXreg_rd(rIOPINS1),
            MAXreg_rd(rIOPINS2));
    return TRUE;
}

/* probe bus to determine device presence and speed */
void MAX_busprobe(void) {
	BYTE bus_sample;

//  MAXreg_wr(rHCTL,bmSAMPLEBUS);
	bus_sample = MAXreg_rd( rHRSL);            //Get J,K status
	bus_sample &= ( bmJSTATUS | bmKSTATUS);      //zero the rest of the byte

	switch (bus_sample) {                   //start full-speed or low-speed host
	case ( bmJSTATUS):
		/*kludgy*/
		if (usb_task_state != USB_ATTACHED_SUBSTATE_WAIT_RESET_COMPLETE) { //bus reset causes connection detect interrupt
			if (!(MAXreg_rd( rMODE) & bmLOWSPEED)) {
				MAXreg_wr( rMODE, MODE_FS_HOST);         //start full-speed host
				xil_printf("Starting in full speed\n");
			} else {
				MAXreg_wr( rMODE, MODE_LS_HOST);    //start low-speed host
				xil_printf("Starting in low speed\n");
			}
			usb_task_state = ( USB_STATE_ATTACHED); //signal usb state machine to start attachment sequence
		}
		break;
	case ( bmKSTATUS):
		if (usb_task_state != USB_ATTACHED_SUBSTATE_WAIT_RESET_COMPLETE) { //bus reset causes connection detect interrupt
			if (!(MAXreg_rd( rMODE) & bmLOWSPEED)) {
				MAXreg_wr( rMODE, MODE_LS_HOST);   //start low-speed host
				xil_printf("Starting in low speed\n");
			} else {
				MAXreg_wr( rMODE, MODE_FS_HOST);         //start full-speed host
				xil_printf("Starting in full speed\n");
			}
			usb_task_state = ( USB_STATE_ATTACHED); //signal usb state machine to start attachment sequence
		}
		break;
	case ( bmSE1):              //illegal state
		usb_task_state = ( USB_DETACHED_SUBSTATE_ILLEGAL);
		break;
	case ( bmSE0):              //disconnected state
		if (!((usb_task_state & USB_STATE_MASK) == USB_STATE_DETACHED)) //if we came here from other than detached state
			usb_task_state = ( USB_DETACHED_SUBSTATE_INITIALIZE); //clear device data structures
		else {
			MAXreg_wr( rMODE, MODE_FS_HOST); //start full-speed host
			usb_task_state = ( USB_DETACHED_SUBSTATE_WAIT_FOR_DEVICE);
		}
		break;
	} //end switch( bus_sample )
}
/* MAX3421E initialization after power-on   */
void MAX3421E_init(void) {
	/* Configure full-duplex SPI, interrupt pulse   */
	SPI_init();
	MAXreg_wr( rPINCTL, (bmFDUPSPI + bmINTLEVEL + bmGPXB)); //Full-duplex SPI, level interrupt, GPX
	MAX3421E_reset();                                //stop/start the oscillator
	if (!max3421_spi_ok) {
		xil_printf("MAX3421E init aborted: SPI link not healthy.\n");
		return;
	}

	//start USB timer
	Status = XTmrCtr_Initialize(&Usb_timer, XPAR_TIMER_USB_AXI_DEVICE_ID);
	if (Status != XST_SUCCESS) {
			xil_printf ("Timer instantiation failed\n");
	}
	XTmrCtr_Start(&Usb_timer, 0);

	xil_printf ("The following should be about 1 second ticks. If they are not, check your timer \n");
	//Test timer to make sure it is plausible
	for (int i = 0; i < 3; i++)
	{
		u32 current = XTmrCtr_GetValue(&Usb_timer, 0);
		while (XTmrCtr_GetValue(&Usb_timer, 0) - current < 100000000)
		{

		}
		xil_printf (".tick.\n");
	}

	/* configure power switch   */
	Vbus_power( OFF);                                      //turn Vbus power off
	//MAXreg_wr( rGPINIEN, bmGPINIEN7); //enable interrupt on GPIN7 (power switch overload flag)
	Vbus_power( ON);
	/* configure host operation */
	MAXreg_wr( rMODE, bmDPPULLDN | bmDMPULLDN | bmHOST | bmSEPIRQ); // set pull-downs, SOF, Host, Separate GPIN IRQ on GPX
	//MAXreg_wr( rHIEN, bmFRAMEIE|bmCONDETIE|bmBUSEVENTIE );                      // enable SOF, connection detection, bus event IRQs
	MAXreg_wr( rHIEN, bmCONDETIE);                        //connection detection
	/* HXFRDNIRQ is checked in Dispatch packet function */
	MAXreg_wr(rHCTL, bmSAMPLEBUS);        // update the JSTATUS and KSTATUS bits
	MAX_busprobe();                             //check if anything is connected
	MAXreg_wr( rHIRQ, bmCONDETIRQ); //clear connection detect interrupt                 
	MAXreg_wr( rCPUCTL, 0x01);                            //enable interrupt pin
}

/* MAX3421 state change task and interrupt handler */
void MAX3421E_Task(void) {
	static u32 poll_div = 0;
	BYTE int_pin;

	if (!max3421_spi_ok) {
		return;
	}
	int_pin = (BYTE)(XGpio_DiscreteRead(&Gpio_int, 1) & 0x01);
	if (int_pin == 0) {
		BYTE hirq = MAXreg_rd(rHIRQ);
		if (hirq != 0x00) {
			xil_printf("MAX interrupt\n\r");
			MaxIntHandler();
		}
	}

	// Poll fallback for attach detect in case INT wiring/level is wrong.
	// This keeps bring-up moving and gives visibility into raw bus state.
	poll_div++;
	if ((poll_div % 50000) == 0) {
		BYTE bus_sample;
		BYTE hirq;

		MAXreg_wr(rHCTL, bmSAMPLEBUS);
		bus_sample = MAXreg_rd(rHRSL) & (bmJSTATUS | bmKSTATUS | bmSE1);
		hirq = MAXreg_rd(rHIRQ);
		xil_printf("poll: INT=%x HIRQ=%x HRSL(JKSE1)=%x state=%x\n", int_pin, hirq, bus_sample, usb_task_state);

		// If USB stack is waiting for device, proactively run bus probe.
		if (usb_task_state == USB_DETACHED_SUBSTATE_WAIT_FOR_DEVICE) {
			MAX_busprobe();
		}
	}
	//if ( IORD_ALTERA_AVALON_PIO_DATA(USB_GPX_BASE) == 1) {
	//	xil_printf("GPX interrupt\n\r");
	//	MaxGpxHandler();
	//}
}

void MaxIntHandler(void) {
	BYTE HIRQ;
	BYTE HIRQ_sendback = 0x00;
	HIRQ = MAXreg_rd( rHIRQ);                  //determine interrupt source
	xil_printf("IRQ: %x\n", HIRQ);
	if (HIRQ & bmFRAMEIRQ) {                   //->1ms SOF interrupt handler
		HIRQ_sendback |= bmFRAMEIRQ;
	}                   //end FRAMEIRQ handling

	if (HIRQ & bmCONDETIRQ) {
		MAX_busprobe();
		HIRQ_sendback |= bmCONDETIRQ;      //set sendback to 1 to clear register
	}
	if (HIRQ & bmSNDBAVIRQ) //if the send buffer is clear (previous transfer completed without issue)
	{
		MAXreg_wr(rSNDBC, 0x00);//clear the send buffer (not really necessary, but clears interrupt)
	}
	if (HIRQ & bmBUSEVENTIRQ) {           //bus event is either reset or suspend
		usb_task_state++;                       //advance USB task state machine
		HIRQ_sendback |= bmBUSEVENTIRQ;
	}
	/* End HIRQ interrupts handling, clear serviced IRQs    */
	MAXreg_wr( rHIRQ, HIRQ_sendback); //write '1' to CONDETIRQ to ack bus state change
}

void MaxGpxHandler(void) {
	BYTE GPINIRQ;
	GPINIRQ = MAXreg_rd( rGPINIRQ);            //read both IRQ registers
}
