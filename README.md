# No! No! No!
A simple nim application to give you the equivalent of duckduckgo bangs, while being lightweight 

## How to use
1) Run nonono(.exe)
2) Open [http://localhost:7878](http://localhost:7878)
3) On Firefox, click on the URL bar and click the NoNoNo icon with a little plus to add it as a search engine
4) Set as default in about:preferences
(I don't have a Chrome browser to give instructions for.)

## How to build
`nim --opt:size -d:release c main.nim`

## How to add a search
### Easy
1) Open [http://localhost:7878](http://localhost:7878)
2) Fill out the form and save
### Manual
1) Open `bangs.txt` in the NoNoNo directory
2) Add a new line with the bang and url separated by a space
