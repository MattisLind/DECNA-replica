# DECNA-replica
An attempt to build a replica of the DECNA Ethernet board for the DEC Prrofessional series of computers.

To start with this repo will just gather thoughts about how to accomplish this project. Hopefully in the future there will be a finished design. On the other hand if I happen to find a DECNA board somewhere this project would probably end right away... But since I have been looking for ten yeasr now I not that confident it will happen.

## Ideas gathered in a non-specific order

* Use 64k x 16 SRAM is shared memory rather than DRAMs.  [Much easier to deal with.](https://www.mouser.se/datasheet/2/198/61C6416AL-258356.pdf). 5V compatible.
* Use [100 pin ATF1508ASL](https://www.mouser.se/datasheet/2/268/atmel_doc0784-1180608.pdf chip) chip to handle most of all random logic on the board. It is even 5V compatible!
* VHDL will be used to create all the random logic. Hopefully this will allow for modifications so that problems that is found can be fixed more easily.
* Use SEEQ DQ8023A encoder chip instead of Fujitsu MB502A. It is directly compatible with the 82586 and doesn't requires level converters or 100 MHz crystal. Should in theory work directly. 
* Use the [Xhomer](https://xhomer.isani.org/xhomer/) project and run it on a Raspi. Create a IO board for the Raspi that enables it to interface with the board (use pin headers for interfacing the raspi rather than the peculiar connector). Write software to make the connection between Xhomer and the real world.
* [DECNA](DECNA.pdf) manual.
* The ```bus command register``` in in DECNA manual is probably not a regsiter but just a decoder of variuous bus operations. Why would it need to be a register, anyhow? Will be handled in the ATF1508.
* Likewise the ```memory address resgister``` is a decoding various strobes into operations. The address lines are latched prior to be decoded. Basically there are four addresses supported by the DECNA. It is unfortunatley not disclosed in the DECNA manual what register go where. Comparing with the other modules gives that at minimum a board shall support an ID register at address 0. As an extension this location would point to a ROM where a pointer is incremented for each read access. Thus able to read out the entire register.There are provisions to reset this pointer register by writing to address 2. The address register is also reset when a INIT signal is asserted.  Comparing with the RAM module giv that the CSR is probably located at address 6 and the memory baser regsiter is at 4.  All this is to be handled in the ATF1508. 
* This section is weird ```The control register interrupt circuit (Figure 3-7) uses signals fromthesystem module to generate an initialize signal (INIT CSR L) that clears the control register. See Table 3-1 for signal descriptions.``` Why would INIT have anything to do with interrupts. I think this something were the person trying to document the thing actually didn't understand what he/she was documenting.
* The ```Control Register ``` is indeed a register (which is by the way cleared by the INIT CSR L signal). It stores information if to access Option ROM or Ethernet Address ROM etc. It is the true CSR register of the DECNA.
* Memory base register is the second register of the DECNA
* The ```ROM data window register``` and ```ROM address register``` are really very fuzzy. Why is it two seprate registers? It is clear from ```Memory Access Register Signal Description``` that we have a ```WRITE ROM``` and a ```READ ROM``` signal. ```READ ROM``` enables the contents of the selected ROM onto the bus and allow us to read through it by automatically increment the address register after each access. The ```WRITE ROM``` signal is used to reset the address register. Makes sense. But the figure 3-13 together with the text doesn't make sense. But I think it is likely that the ```ROM data window register``` is not at all a register but just the data from the ROM. Presuambly the person who once doumented this didn't have a clue and the engineer who designed it never bothered to review the documentation. Actually normally DEC documentation is very very good. I think this is the crappiest ever DEC technical document I ever have read.
* The Memory section is probably quite straight forward. It will require a state machine that synchronzises accesses to the shared memory. Static memory removes the need for a memory controller. The state machine need to be driven by some clock signal. I think that the 10 MHz Ethernet signal can be used for this. We still will need all the latches and buffers so that data can be read and stored and let the other entity to take control of the memory.
* Create an emulated DECNA device in Xhomer to experiment with. There is an 82586 device in Mame. How can we have two CPUs executing instructions inside Xhomer? There is an eventqueue? To start with we just want to understand which regiuster go where. If we can verify that the Pro CPU is uploading code to the shared memory we are good to go.
* The Pro motherboard are using inverting bus tranceivers 8307 and it is likely that the same chip is on the DECNA as well since the memory expansion board seems to use it as well. I think these can be replaced with 74LS640 or 74ALS640.
* Is the 82586 running in MAXIMUM or MINIMUM mode? Pin 33 grounded or not? It is now checked. It is connected to ground which means MAXIMUM mode. MAXIMUM mode means that signals S0 and S1 are generated by the 82586 and connected to the 8288 chip. If any of the signals S0 or S1 are low this indicate a start of a memory cycle and signals ~ALE, ~WR, ~RD, ~ALE, ~DEN, DT/~R are generated.  [8288 datasheet](intel_8288_datasheet.pdf)
* The ARDY/SRDY (pin 37) on the 82586 is grounded.
* The XACKAL signal (pin 2) from the 8207 is connected to (pin 11) Latch Enable on a 74LS373 meaning that when data is ready it is latched in the 74LS373 chip. I wonder if the XACKAL signal go somewhere else as well? I.e. involved in generating the BRPLY to the CTI bus?
* Pin 17 of the MB502A Ethernet encoder decoder chip is connected to Vcc, this means that the signals from the MB502A to the transceiver is set up for an AC coupled path, i.e. a transformer.
* The 82586 clock and ethernet serial data inputs need MOS levels. Use a 74ACT14 to get proper MOS levels.

### Some good info on the DECNA from Bjoren Davis

I've done some work with the DECNA boards (I wrote a DECNA emulator for an Xhomer fork that more or less works -- it even booted disklessly). So I had to do a bunch of reverse engineering.
The diagnostic ROM runs through 10 separate tests at its start:
#### Test1: 
Tests the ID ROM (which contains the MAC address) and does some initial testing on the dual-ported RAM. When it fails for the following reasons it yields the following codes (numbers are in octal):
##### Failure 001: 
Bus error reading ID ROM
##### Failure 002: 
Inconsistency in ID ROM contents: checksum invalid, MAC address is all 0s, bit 0 in the second MAC word is 1.
##### Failure 003: 
Failure to map dual ported RAM to physical address 0o05000000
##### Failure 004: 
Readback on MEM register isn't 012, inverted (using COMB) MEM register doesn't read back properly, write of 007 to MEM register doesn't read back, inverted (using COMB) MEM register doesn't read back properly. When this part succeeds it leaves the dual-ported RAM mapped at 0o14000000
##### Failure 005: 
Attempt to write first word of the dual-ported RAM yields a bus error
##### Failure 006: 
*Failure to see a bus error* when clearing ME in CTL and repeating test from previous step. After this step the DP RAM is unmapped.
#### Test2: 

Tests the dual ported RAM in earnest. This test maps the 128 KiB DP RAM to physical address 0o14000000..0o14377777 and turns on access in the CTL register.
It then maps 4 pages (32 KiB) at a time of the DP RAM to virtual address space 020000..117777. It repeats this, moving the 32 KiB window over the 128 KiB of DP RAM on the board. For each of these mappings it does a series of tests. If any of these tests fails it posts failure codes 010 (for DP RAM offsets 0300000..0377777), 011 (for DP RAM offsets 200000..277777), 012 (for DP RAM offsets 100000..177777), or 012 (for DP RAM offsets 000000..077777)
It then waits for a bit and back to read the first word of shared RAM and makes sure it's the pattern it last wrote (052525). If it's not then it posts error 013. On successful completion it leaves the highest 8 KiB of DP RAM (PA 0o14360000..0o14377777, which corresponds to DP RAM offsets 0360000..0377777) mapped at virtual address 020000...037777).
I haven't really worked through the details of the remaining 8 tests.


Concerning the discussion of the CTI option ROM: the DECNA actually contains 2 completely separate position-independent code blocks: the diagnostic ROM and the network boot ROM (to boot a diskless client system).
Every CTI option ROM starts with the following header:

|Offset	| Size	| My name	| Value on DECNA	|  Description |
|-------|-------|---------|-----------------|--------------|
| 000	  |  word | ID	    |  0000042	      |   The CTI board ID. Because the CTI option ROM is read byte at a time boards that don't implement a real ROM will simply return a single byte for the ID and everything else (e.g., 004 for the floppy controller). Because the ID is a 16-bit word, in such a case the byte is read twice (e.g., 004 * 0400 + 004 = 002004). This is why all the non-ROM CTI boards have IDs with the same high and low bytes.
| 002	 | word	 | MAGIC	| 0125377	|    This is a pattern that the system boot ROM will recognize as indicating that the CTI board actually has a ROM.
|004	| byte	| FLAGS	|   004	| I'm guessing this is flags. The DECNA board is the only one with a non-zero value in it, so I'm guessing 004 means "bootable".
|005	|byte	|NSECS	|002	|The number of sections (and section headers) to follow.
|006	| word	|ROMSIZ	|000040	|The overall size of the ROM, in bytes, divided by 256.
|010	|word	|?	|000000 |	All zero. I'm not sure what this is.

This is then followed by the two section headers:
| ROM offset	|Header offset|	Size |	My name	 |DECNA value | Description |
|-------------|-------------|------|-----------|-----------|--------------|
| 012	  |000	|5 words	|SECTYP|	0042046, 0000000, 0000000, 0000000, 0000000	|Identifies the section type. 0042046 just happens to be "&D", and this section is the Diagnostic section. Other possible values are 00410046 + [0]*4 ("&B") for boot sections, 00530046 ("&V") for I have no idea, and 00500046 ("&P") also for something I don't know.
|024	|012	|3 bytes	|SECOFF|	000000052|	ROM byte-offset of the beginning of this actual section.
|027	|015	|word	|SECLEN	|0012040	Size (in bytes) of section
|031	|017 |	byte	|-|	0	|Must be 0|
|032	|000	|5 words	|SECTYP|	0041046, 0000000, 0000000, 0000000, 0000000	|Boot ("&B") section ID
|034	|012	|3 bytes	|SECOFF	|000012112	|ROM offset of the beginning of this actual section.
|037	|015	|word	|SECLEN	|0003742	|Size (in bytes) of section
|041	|017	|byte|	- |	0 |	Must be 0 |

So the diagnostic code you want to disassemble starts at ROM byte offset 000000052. I'm attaching a very raw and barely annotated disassembly that I've worked from.
Note that the last word of each of these two sections contains a dedicated checksum word that covers its contents, and similarly the entire ROM ends with a checksum word that covers the whole thing.
The system boot ROM will load the entire contents of a CTI option ROM section (up to 0o60000 bytes worth) at RAM location 02000 and it will then jump to that first location.
Before making the jump the system boot ROM sets up R1 with the CTI slot number (0..5 for the PC325/PC350, 0...6 for the PC380) and makes the jump. The system ROM provides some support code that is accessible via EMTs:
|EMT number	|My name	|Inputs	|Outputs|	Description|
|-----------|---------|-------|-------|------------|
|0	| CTRSM	| None	| None	|Doesn't return. Resumes back in the system boot ROM.
|1	|CTFIND	 |R0: CTI card ID (e.g., 0000042)|	R0: CTI slot index 0..6 or -1 on failure	|Looks through the soft configuration data to see if it has seen the given CTI card ID. Returns the slot number if it finds such a card, -1 on failure.
|2	|ICENB	|R1: (Interrupt controller # (0..2) << 6 | interrupt channel (0..7))|	None	|Executes "Clear Single IRR and IMR" for the given controller and channel. This enables the given interrupt.
|3	|ICDIS	|R1: (Interrupt controller # (0..2) << 6 | interrupt channel (0..7))|	None	| Executes "Set Single IMR Bit" for the given controller and channel. This disables the given interrupt.
|4	|ICTST	|R1: (Interrupt controller # (0..2) << 6 | interrupt channel (0..7))|	None	|Executes "Set Single IRR Bit" for the given controller and channel. This creates a software-generated interrupt.
|5	|KMAP	|-4(sp) number of 8 KiB pages to map (0..4)  -2(sp) High 9 bits of physical address.	|None	|Stores KIPAR1-4 into 01120, 01116, 01114, 01112, and then reprograms them to map the required space. Also sets bit 04000 in the UIPAR0 to indicates that KIPAR1-4 are stored in RAM.
|6	|KUMAP	|None|	None	|Restores KIPAR1-KIPAR4 from values stored in 01120, 01116, 01114, 01112 only if bit 04000 is set in UIPAR0. Then clears bit 04000 in UIPAR0.

Hopefully that will give you more information to help you decode what's going on in the diagnostic ROM.
If you get further into it you'll need http://bitsavers.org/components/intel/ethernet/i82586.pdf and an app note in [http://bitsavers.org/components/intel/_dataBooks/1991_Microcommunications.pdf](http://bitsavers.org/components/intel/_dataBooks/1991_Microcommunications.pdf) (pp. 1-337 to 1-417).
IIRC you should be forewarned: the datasheet is actually wrong in several important places. Off the top of my head I seem to recall it is wrong about the top-level shared RAM structure used by the i82586. The top-level "System Configuration Pointer" in the block at the last 10 bytes of memory does not point to the system configuration block (SCB). Instead, it points to something called an "intermediate system configuration pointer" (ISCP) which then points to the SCB. This is mentioned in the app note. Ugh.
--Bjoren

### Signals to map onto the ATF1508 CPLD

| Signal | Source / Destination | Pin | Comment |
|--------|--------|-----|-------|
| RESET  | 82586  | 34 |
| INT    | 82586  | 38  |
| CLK    | 82586  | 32  | Need MOS buffer from the ATF1508 |
| AD0    | 82586  | 6   | Needed to create High or Low write enable |
| A17 -A23 | 82586 | 3-5, 45-47 | Maybe not needed since the internal dual port memory will become aliased over the entire 16 meg space |
| CA      |  82586 | 35 |  Channel attention |
| /BHE    |  82586  | 44 | To create the high and low write enable together with A0 |
| READY   |  82586  | 39  | Ready signal - either this or ARDY/SRDY is to be used. |
| ARDY/SRDY | 82586 | 37  | See above
| /S0 /S1   | 82586 | 40, 41 | To generate all the read and write signals |
| A1 - A6 | CTI  |  - | Input to IO port selection. Connected to the bus buffer DP8307 or the like |
| SSxL   | CTI  | 29 | Slot select signal - already latched |
| BIOSELL | CTI  | 43  | IO Select signal - need latching like address signal |
| BWHBL   | CTI  | 23  | Bus Write High Byte Low |
| BWLBL   | CTI | 21 |   Bus Write Low Byte Low |
| BWRITEL | CTI | 19 |   Bus Write Low |
| BDSL    | CTI | 37 |  Bus Data Strobe Low |
| BASL    | CTI | 39 |  Bus Address Strobe Low |
| BSDENL  | CTI | 25 |  Bus Slave Data Enable Low |
| BMDENL  | CTI | 17 |  Bus Master Data Enable Low |
| BINITL  | CTI | 5  | Bus Init Low |
| BDCOKH | CTI | 1  |  Bus DC OK High |
| BRPLYL | CTI | 13 | Bus Reply Low |
| IRQBnL | CTI | 31 | Interrupt B |
| IRQAnL | CTI | 33 | Interrupt A | 
| SCK    | EEPROM | - | SPI CLOCK |
| nHOLD  | EEPROM  | - | Hold signal |
| nCS    |  EEPROM | - | EEPROM Chip Select |
| MOSI   | EEPROM | - | EEPROM MOSI |
| MISO   | EEPROM | - | EEPROM MISO |
| D0-D7  | CTI    | - | Databus for IO signals |
| CRS    | 8023   | - | Carrier sense from encoder / decoder - flip-flop is set when there is a transistion on this signal (?) - Check with the xhomer DECNA driver by Bjoren how this should work |
| TEN    | 82586  | - | Transmit enable - potentially clearing the carrier sense flip-flop |
| LOOPBACK | 8023 | - | Set up loopback
| WRCLKA | DPRAM | -  | Write register clock port A |
| WROEA  | DPRAM | -  | Port A Write register OE |
| RDCLKA | DPRAM | -  | Read register clock port A |
| RDOEA  | DPRAM | -  | Port A Read register OE |
| WRCLKA | DPRAM | -  | Write register clock port B |
| WROEA  | DPRAM | -  | Port B Write register OE |
| RDCLKA | DPRAM | -  | Read register clock port B |
| RDOEA  | DPRAM | -  | Port B Read register OE |
| ASA    | DPRAM | -  | Port A address Strobe = BASL ? |
| AOEA   | DPRAM | -  | Port A Address OE |
| AOEB   | DPRAM | -  | Port B Address OE |
| ASB    | DPRAM | -  | PORT B address Strobe |  
| MOE    | MEM   | -  | Memory OE |
| MWE    | MEM   | -  | Memory WE |
| MUBE   | MEM   | -  | Memory Upper Byte Enable |
| MLBE   | MEM   | -  | Memory Lower Byte Enable |
| MCE    | MEM   | -  | Memory Chip Enable |
| CLKIN  | CLK   | -  | 32 MHz general clock input |
