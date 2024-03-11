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
* Is the 82586 running in MAXIMUM or MINIMUM mode? Pin 33 grounded or not? It is now checked. It is connected to ground which means MAXIMUM mode. 
  
