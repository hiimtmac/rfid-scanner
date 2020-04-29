# rfid-scanner

Currently bug on IRQ pull setting.

Must run `sudo python main.py` first before `sudo swift run` will work.

### usbmount

`usbmount` is broken for 18.04 through apt

```sh
apt-get install debhelper build-essential
git clone https://github.com/rbrito/usbmount.git
cd usbmount
sudo dpkg-buildpackage -us -uc -b
# cd ..
# sudo dpkg -i usbmount_0.0.24_all.deb
```
