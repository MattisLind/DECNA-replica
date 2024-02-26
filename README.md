# DECNA-replica
An attempt to build a replica of the DECNA Ethernet board for the DEC Prrofessional series of computers.

To start with this repo will just gather thoughts about how to accomplish this project. Hopefully in the future there will be a finished design. On the other hand if I happen to find a DECNA board somewhere this project would probably end right away... But since I have been looking for ten yeasr now I not that confident it will happen.

## Ideas gathered in a non-specific order

* Use 64k x 16 SRAM is shared memory rather than DRAMs.  [Much easier to deal with.](https://www.mouser.se/datasheet/2/198/61C6416AL-258356.pdf). 5V compatible.
* Use [100 pin ATF1508ASL](https://www.mouser.se/datasheet/2/268/atmel_doc0784-1180608.pdf chip) chip to handle most of all random logic on the board. It is even 5V compatible!
* Use SEEQ DQ8023A encoder chip instead of Fujitsu MB502A. It is directly compatible with the 82586 and doesn't requires level converters or 100 MHz crystal. Should in theroy work directly. 
* Use the [Xhomer](https://xhomer.isani.org/xhomer/) project and run it on a Raspi. Create a IO board for the Raspi that enables it to interface with the board (use pin headers for interfacing the raspi rather than the peculiar connector). Write software to make the connection between Xhomer and the real world.
* 
