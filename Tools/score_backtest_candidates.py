#!/usr/bin/env python
"""Score legacy, Gen-4, and Gen-5 candidates; emit window-level evidence."""
from __future__ import annotations
import argparse,csv,json,re
from collections import defaultdict
from pathlib import Path

def number(v):
 m=re.search(r'-?[0-9][0-9 ]*(?:\.[0-9]+)?',str(v));return float(m.group(0).replace(' ','')) if m else 0.0
def dd(v):
 m=re.search(r'\(([0-9.]+)%\)',str(v));return float(m.group(1)) if m else 0.0
def parse(run):
 m=re.match(r'(.+)_WF([123])_(FIT|VALIDATE)$',run)
 if m:return m.group(1),'WF'+m.group(2),m.group(3)
 m=re.match(r'(.+)_(SELECT_DEV|SELECT_VALIDATE)$',run)
 if m:return m.group(1),'LEGACY','DEV' if m.group(2).endswith('DEV') else 'VALIDATE'
 m=re.match(r'(.+)_(Y20\d\d)$',run)
 if m:return m.group(1),m.group(2),'ANNUAL'
 raise ValueError(run)
def metrics(run,j,meta,rows):
 p=[float(x['net_profit']) for x in rows]; pos=sum(x for x in p if x>0);neg=-sum(x for x in p if x<0)
 return {'run_id':run,'from_date':meta.get('FromDate'),'to_date':meta.get('ToDate'),'net_profit':round(sum(p),8),'profit_factor':round(pos/neg,8) if neg else None,'trade_count':int(number(j.get('TotalTrades',0))),'buy_count':sum(x.get('direction')=='BUY' for x in rows),'sell_count':sum(x.get('direction')=='SELL' for x in rows),'position_count':len(rows),'test_completed':bool(j.get('TestCompleted')),'errors':list(j.get('Errors') or [])}
def main():
 a=argparse.ArgumentParser();a.add_argument('--runs-root',required=True);a.add_argument('--positions-csv',required=True);a.add_argument('--output',required=True);a.add_argument('--min-validation-positions',type=int,default=100);a.add_argument('--allow-holdout',action='store_true');x=a.parse_args()
 rows=defaultdict(list)
 with Path(x.positions_csv).open(encoding='utf-8-sig',newline='') as h:
  for r in csv.DictReader(h):
   if not x.allow_holdout and int(r['entry_year'])>=2025:raise SystemExit('HOLDOUT GUARD')
   rows[r['run_id']].append(r)
 candidates=defaultdict(lambda:defaultdict(dict))
 for p in Path(x.runs_root).glob('*/journal.json'):
  try:cid,win,stage=parse(p.parent.name)
  except ValueError:continue
  j=json.loads(p.read_text(encoding='utf-8-sig'));mp=p.parent/'run-metadata.json';meta=json.loads(mp.read_text(encoding='utf-8-sig')) if mp.exists() else {}
  candidates[cid][win][stage]=(j,meta)
 if not candidates:raise SystemExit('No paired candidate journals found')
 out=[]
 for cid,wins in sorted(candidates.items()):
  windows={}; reasons=[]
  for win,stages in sorted(wins.items()):
   windows[win]={}
   for st,(j,m) in stages.items():
    run=next(p.parent.name for p in Path(x.runs_root).glob('*/journal.json') if p.parent.name and parse(p.parent.name)==(cid,win,st))
    windows[win][st]=metrics(run,j,m,rows[run])
   if 'VALIDATE' in windows[win]:
    v=windows[win]['VALIDATE']; journal_pf=number(stages['VALIDATE'][0].get('ProfitFactor',0)); pf=journal_pf if win=='LEGACY' else v['profit_factor']
    prefix='validation' if win=='LEGACY' else win
    if pf is None or pf<1.10:reasons.append(f'{prefix}:pf_below_1.10')
    if v['net_profit']<=0:reasons.append(f'{prefix}:nonpositive_expectancy')
    if v['position_count']<x.min_validation_positions:reasons.append(f'{prefix}:positions_below_{x.min_validation_positions}')
    if v['errors']:reasons.append(f'{prefix}:material_execution_error')
   elif 'ANNUAL' not in windows[win]:
    reasons.append(f'{win}:missing_validation')
  row={'candidate_id':cid,'passed':not reasons,'fail_reasons':reasons,'windows':windows}
  if 'LEGACY' in windows:
   row['dev']=windows['LEGACY'].get('DEV',{});row['validation']=windows['LEGACY'].get('VALIDATE',{})
  if any('ANNUAL' in stages for stages in windows.values()):
   all_annual=[windows[y]['ANNUAL'] for y in sorted(windows) if 'ANNUAL' in windows[y]]
   tot_p=sum(w['net_profit'] for w in all_annual); tot_t=sum(w['trade_count'] for w in all_annual); tot_b=sum(w['buy_count'] for w in all_annual); tot_s=sum(w['sell_count'] for w in all_annual)
   row['annual_summary']={'net_profit':round(tot_p,8),'trade_count':tot_t,'buy_count':tot_b,'sell_count':tot_s,'years_tested':len(all_annual)}
  out.append(row)
 payload={'schema_version':2,'passed_count':sum(x['passed'] for x in out),'candidates':out}
 Path(x.output).write_text(json.dumps(payload,indent=2),encoding='utf-8');print(f'CANDIDATES SCORED: total={len(out)} passed={payload["passed_count"]}')
if __name__=='__main__':main()
