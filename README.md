# ipviz

Transforms a list of json subnets to a heatmap png

Based on https://github.com/measurement-factory/ipv4-heatmap

```
Transforms a list of subnets with allocated ips in a simple heatmap png
=======================================================================
usage: $PROGRAM [OPTIONS] [-c cidr_limit] [-o output_png] [-t aws|simple] input_json

OPTIONS:
    -d : Debug output
    -? : This message
    -t : Input format type:
          AWS (default): Format as aws ec2 describe-subnets --output json
          SIMPLE : Format see below
    -c CIDR
       Limit the output to this CIDR
       Default to /16 subnet of the lowest IP in input
    -o output_png
       defaults to heatmap_<baseip_of_cidr>.png
    -r : Export input file as enhanced output file compatible with SIMPLE File format

input_json:
    file with json array and the following object structure:
    SIMPLE:
    [
      {
        "cidr": "10.107.0.0/28",
        "available": 5,
        "name": "public az1",
        "az": "eu-central-1"
      },
      {
        "cidr": "10.107.0.64/28",
        "available": 2,
        "name": "public az2",
        "az": "eu-central-1"
      }
    ]
 or
    AWS:
    Output as in aws ec2 describe-subnets ...

* each subnet is rendered as a block in the heatmap
* the allocated ips in a subnet are filled from left/top to right/down
* the free ips are rendered with a random background color in the block

Required tools:
 - ipv4-heatmap "make install" from: https://github.com/measurement-factory/ipv4-heatmap
 - jq
 - imagemagick
 - ipcalc
 - nmap
 - grepcidr


```

## Example

`./ipviz.sh -r -o examples/example_1.png -t simple examples/example_1.json`

Input:

[Heatmap Example 1](examples/example_1.json)

Output:

![Heatmap Example 1](examples/example_1.png)
