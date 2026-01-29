#!/usr/bin/env python3
import argparse
import hjson
import pathlib
from mako.lookup import TemplateLookup

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-c', '--config', required=True)
    parser.add_argument('-o', '--output', required=True)
    parser.add_argument('-t', '--template', required=True)
    parser.add_argument('-d', '--template_dir', required=True)
    args = parser.parse_args()

    with open(args.config, 'r') as f:
        raw_cfg = hjson.load(f)

    # REPLICATING SnitchClusterTB / SnitchCluster structure
    cluster_cfg = raw_cfg.get('cluster', raw_cfg)
    if 'cores' in cluster_cfg:
        cluster_cfg['nr_cores'] = len(cluster_cfg['cores'])
    
    # The template expects 'cfg' to be the top-level object containing 'cluster'
    final_cfg = {
        'cluster': cluster_cfg,
        **{k: v for k, v in raw_cfg.items() if k != 'cluster'}
    }

    lookup = TemplateLookup(directories=[args.template_dir])
    
    try:
        tmpl = lookup.get_template(args.template)
        # Original used render_unicode; for Python 3, render() is standard
        with open(args.output, 'w') as f:
            f.write(tmpl.render(cfg=final_cfg))
    except Exception as e:
        import traceback
        print(f"Error rendering {args.template}: {e}")
        # traceback.print_exc() # Uncomment if you hit more hidden KeyErrors
        exit(1)

if __name__ == "__main__":
    main()
