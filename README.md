# Project Title
Distributed Operating System Principles Project 3

## Group Members Info 
1) DAKSH GAUTAM - 11055891
2) SARTHAK CHAUHAN  - 71835321

## Compiling and Running

Steps that tell you how to get project running.

1) Download and extract the zip file. 
2) Open CMD and navigate to the folder in the unzipped project.
3) Run the following commands
   ``` 
   mix escript.build
   # ./chord <number_of_nodes> <number_of_message_requests>
   ./chord 1000 3
   
   ```
   - number_of_nodes = any integer
   - number_of_message_requests = any integer

  **The arguments can be changed here. The first number specifies the number of nodes, the second specifies the number of requests** 

## What is working ?
 - The chord protocol is fully working along with the failure model for Bonus Part.
  
## Largest Problem Solved
- number of nodes = 8000 and number of requests = 4

## Built With
* [Elixir](https://elixir-lang.org/)
* [Mix](https://elixir-lang.org/getting-started/mix-otp/introduction-to-mix.html)