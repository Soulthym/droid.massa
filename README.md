# droid.massa
An easy installer to run massa tools on a smartphone
[droid.massa](https://droid.deweb.half-red.net)

## How to use
1. Download and install the official [Termux apk from F-Droid](https://f-droid.org/packages/com.termux/).
2. Open Termux, copy and run the following command:
```bash
bash <(curl -sL https://droid.deweb.half-red.net/install.sh)
```
3. Select the desired option with up/down arrows and Space key, then press Enter to confirm.
4. Wait for the installation to finish.
5. Restart termux to apply the changes (type 'exit' and press ENTER, then open termux again)
6. Run the installed tool by typing its name in the terminal:
```bash
massa
```
```bash
deweb
```

## Tools
Currently supported tools:
- [massa](https://github.com/massalabs/massa): A validator for the massa blockchain
- [DeWeb](https://github.com/massalabs/DeWeb): A client to access massa's Decentralized Web

## License
This project is distributed under the MIT License - see the [LICENSE](src/LICENSE) file
or header of the [installation script](src/install.sh) for more information.
