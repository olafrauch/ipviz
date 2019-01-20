# ipviz

Transforms a list of json subnets to a heatmap png

Highlights:

* Visualize your aws subnets as map to get an overview of available IP ranges and ip usage of each subnet.
* Accepts input as
  * Feed with output from `aws ec2 describe-subnets --output json`
  * Simple JSON based list for custom input
* Produces the following output:
  * PNG with a heatmap like usage vizualisation
  * (optional) JSON report with usage metrics of the subnets in an 'enhanced simple input format' for further processing

Based on https://github.com/measurement-factory/ipv4-heatmap

Find ready to run [Docker images in my dockerhub repo](https://cloud.docker.com/u/olafrauch/repository/docker/olafrauch/ipviz)

Run them e.g. with 
`aws ec2 describe-subnets --output json | docker run -t --rm olafrauch/ipviz:1.0.5`

```
Transforms a list of subnets with allocated ips in a simple heatmap png
=======================================================================
usage: ipviz.sh [OPTIONS] [-c cidr_limit] [-o output_png] [-t aws|simple] input_json|STDIN

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
    file or stdin with json array and the following object structure:
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

or

`cat examples/example_1.json | ./ipviz.sh -r -o examples/example_1.png -t simple`


Input:

[Heatmap Example 1](examples/example_1.json)

Output:

![Heatmap Example 1](examples/example_1.png)
