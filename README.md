# DNS test

Test DNS server with DOH, DOT, DNS and run ping test with IPv4 and IPv6.

Test is run with [Adam:one](https://adamnet.works/) on pfSense

## Requirements:
<ol>
 <li>Currently only support linux, not tested on mac or windows.
<li> Needs python with modules installed:
   <ol>
     <li>Prettytable</li>
   </ol>
</ol>


### Installing python modules:
```
python -m pip install -U prettytable
```
or
```
python3 -m pip install -U prettytable
```
if the above fails,
for debian or ubuntu based:
```
sudo apt install python3-prettytable
```
for arch based
```
sudo pacman -S python3-prettytable
```

### To run locally
```
git clone https://github.com/w1tw0lf/DNS_test.git
cd DNS_test/
./dns_test.sh
```