from prettytable import PrettyTable
import json
import subprocess

with open("doh6_output", "r") as file:
    doh6_data = file.read()
with open("doh4_output", "r") as file:
    doh4_data = file.read()


doh6_data_json = json.loads(doh6_data)
doh4_data_json = json.loads(doh4_data)
answers6 = doh6_data_json.get("Answer", [])
answers4 = doh4_data_json.get("Answer", [])
table = PrettyTable()
table.field_names = ["Address"]
for answer4 in answers4:
    table.add_row(
        [
            answer4.get("data", ""),
        ]
    )
for answer6 in answers6:
    table.add_row(
        [
            answer6.get("data", ""),
        ]
    )    
print("")
print("DOH results")
print(table)

with open('dot', 'r') as file:
    lines = file.readlines()
with open('dot6', 'r') as file6:
    lines6 = file6.readlines()    

table = PrettyTable(['Address'])
for line in lines:
    address = line.strip()
    table.add_row([address])
for line in lines6:
    address = line.strip()
    table.add_row([address])    

print("")
print("DOT results")
print(table)


with open('dns', 'r') as file:
    lines = file.readlines()
with open('dns6', 'r') as file6:
    lines6 = file6.readlines()    

table = PrettyTable(['Address'])
for line in lines:
    address = line.strip()
    table.add_row([address])
for line in lines6:
    address = line.strip()
    table.add_row([address])              

print("")
print("DNS results")
print(table)

with open('ping_results.json', 'r') as json_file:
    data = json.load(json_file)
if len(data["results"]) == 4 :
    data["results"].insert(4, "time=N/A")
    data["results"].insert(5, "time=N/A")
    data["results"].insert(6, "time=N/A")
    data["results"].insert(7, "time=N/A")
table = PrettyTable()
table.field_names = ["IPv4", "IPv6"]
table.add_row([data["results"][0].replace("time=", ""), data["results"][4].replace("time=", "")])
table.add_row([data["results"][1].replace("time=", ""), data["results"][5].replace("time=", "")])
table.add_row([data["results"][2].replace("time=", ""), data["results"][6].replace("time=", "")])
table.add_row([data["results"][3].replace("time=", ""), data["results"][7].replace("time=", "")])
print("")
print("Ping results")
print(table)


