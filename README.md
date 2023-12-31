# DNS test

Test DNS server with DOH, DOT, DNS and run ping test with IPv4 and IPv6.

Test is run with [Adam:one](https://adamnet.works/) on pfSense

<img
  src="/assets/results.png"
  alt="Results"
  title="Results"
  style="display: inline-block;">

## Requirements:
<ol>
 <li>Currently supports linux and mac. It should run on windows in WSL *not tested*
<li> Needs python with modules installed:
   <ol>
     <li>Prettytable</li>
   </ol>
</ol>


### Installing python modules:
```
pip install -U prettytable
```
or
```
pip3 install -U prettytable
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
More info on [WSL](https://learn.microsoft.com/en-us/windows/wsl/install)

### To run locally
```
git clone https://github.com/w1tw0lf/DNS_test.git
cd DNS_test/
./dns_test.sh
```
### Possible issues

1. On older macOS, you might find that it gives an issue with dig command, fix is to update bind via brew witth ```brew install bind```
