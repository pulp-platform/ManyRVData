#!/usr/bin/env python3

# Copyright 2025 ETH Zurich and University of Bologna.
#
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Author: Zexin Fu <zexifu@iis.ee.ethz.ch>
from graphviz import Digraph

# Create a Digraph object
dot = Digraph(format='png')
# dot.attr(rankdir='LR', fontsize='10')
dot.attr(rankdir='TB', fontsize='10')

# Define global styles
dot.attr('node', shape='rectangle', style='filled', fillcolor='lightgray', fontname='Helvetica')
dot.attr('edge', fontname='Helvetica')

# Nodes for init
dot.node('start', 'Start')
dot.node('core_id', 'Get core_id = snrt_cluster_core_idx()')
dot.node('core0?', 'core_id == 0?', shape='diamond', fillcolor='lightblue')

# Core 0: Initialization
dot.node('init_xbar', 'Set XBAR policy')
dot.node('init_mm', 'Initialize memory management runtime')
dot.node('init_rlc', 'Initialize RLC runtime\n- Initialize RLC struct variables\n' \
                     '- Initialize to_send and sent linked lists\n')
dot.node('init_locks', 'Initialize spinlocks\n- tosend_llist_lock\n- sent_llist_lock\n- mm_lock', shape='rectangle')

# Barrier
dot.node('barrier', 'snrt_cluster_hw_barrier()')

# Split paths
dot.node('rlc_start', 'rlc_start(core_id)')

# Consumer (Core 0)
dot.node('core0_loop', 'Consumer Loop (Core 0)', shape='rectangle', fillcolor='lightyellow')
dot.node('pop_node', 'Pop node from tosend llist\n(lock: tosend_llist_lock)', shape='rectangle')
dot.node('is_null?', 'Node == NULL?', shape='diamond', fillcolor='lightblue')
dot.node('wait_retry', 'Retry (wait)', shape='rectangle')
dot.node('data_move', 'Vector Copy from src to tgt', shape='rectangle')
dot.node('rlc_update', '- Increment pduWithoutPoll, byteWithoutPoll;\n' \
                       '- Decrement to_send llist sduNum, sduBytes;\n' \
                       '- Increment vtNext;\n - Increment sent_llist sduNum, sduBytes', shape='rectangle')
dot.node('push_sent', 'Push to sent llist\n(lock: sent_llist_lock)', shape='rectangle')
dot.node('ack_check', 'Sent llist size ≥ 6?\n(simulate reveiving ACK from UE,\nand the ACK_SN is 2 pkg)', shape='diamond', fillcolor='lightblue')
dot.node('ack_handle', '- Pop sent_llist to ACK_SN node, and free the nodes; (lock: mm_lock)\n' \
                       '- Increment vtNextAck;\n- Decrement sent_llist sduNum, sduBytes', shape='rectangle')

# Producer (Core 1..N)
dot.node('producer_loop', 'Producer Loop (Core 1..N)', shape='rectangle', fillcolor='lightyellow')
dot.node('get_pkgid', 'Receive new pkg from PDCP\n', shape='rectangle')
dot.node('alloc_node', 'Allocate Node with mm_alloc()\n(lock: mm_lock)', shape='rectangle')
dot.node('alloc_null?', 'node == NULL?\n(out of memory)', shape='diamond', fillcolor='lightblue')
dot.node('retry_alloc', 'Wait, Retry Allocation', shape='rectangle')
dot.node('fill_node', 'Initialize Node:\n- Set src, tgt, size etc.\n- Set pointers', shape='rectangle')
dot.node('push_tosend', 'Push Node to tosend llist\n(lock: tosend_llist_lock)', shape='rectangle')


# Edges: common start
dot.edge('start', 'core_id')
dot.edge('core_id', 'core0?')
dot.edge('core0?', 'init_xbar', label='Yes')
dot.edge('init_xbar', 'init_mm')
dot.edge('init_mm', 'init_rlc')
dot.edge('init_rlc', 'init_locks')
dot.edge('init_locks', 'barrier')
dot.edge('core0?', 'barrier', label='No')
dot.edge('barrier', 'rlc_start')

# Split into roles
dot.edge('rlc_start', 'core0_loop', label='core_id == 0')
dot.edge('rlc_start', 'producer_loop', label='core_id > 0')

# Consumer path
dot.edge('core0_loop', 'pop_node')
dot.edge('pop_node', 'is_null?')
dot.edge('is_null?', 'wait_retry', label='Yes')
dot.edge('wait_retry', 'pop_node')
dot.edge('is_null?', 'data_move', label='No')
dot.edge('data_move', 'rlc_update')
dot.edge('rlc_update', 'push_sent')
dot.edge('push_sent', 'ack_check')
dot.edge('ack_check', 'ack_handle', label='Yes')
dot.edge('ack_check', 'pop_node', label='No')
dot.edge('ack_handle', 'pop_node')

# Producer path
dot.edge('producer_loop', 'get_pkgid')
dot.edge('get_pkgid', 'alloc_node')
dot.edge('alloc_node', 'alloc_null?')
dot.edge('alloc_null?', 'retry_alloc', label='Yes')
dot.edge('retry_alloc', 'alloc_node')
dot.edge('alloc_null?', 'fill_node', label='No')
dot.edge('fill_node', 'push_tosend')
dot.edge('push_tosend', 'get_pkgid')

# Save the file
dot.render('../data/rlc_flowchart', cleanup=False)
