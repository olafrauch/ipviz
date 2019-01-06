# ipviz

Transforms a list of json subnets to a heatmap png

```
Transforms a list of subnets with allocated ips in a simple heatmap png
=======================================================================
usage: ipviz.sh [OPTIONS] [-c cidr_limit] input_json [output_png]

OPTIONS:
    -d : Debug output
    -? : This message
    -c CIDR
       Limit the output to this CIDR
       Default: 0.0.0.0/0

input_json:
    file with json array and the following object structure:
    [
      {
        "cidr": "10.107.0.0/28",
        "available_ips": 5,
        "name": "public az1"
      },
      {
        "cidr": "10.107.0.64/28",
        "available_ips": 2,
        "name": "public az2"
      }
    ]

output_png:
    Defaults to heatmap_<baseip_of_cidr>.png

Required tools installed:
 - ipv4-heatmap "make install" from: https://github.com/measurement-factory/ipv4-heatmap
 - jq
 - imagemagick
 - ipcalc
 - prips

```