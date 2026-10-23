"""Summarize raw native input/timing observations, retaining every slow frame."""
from pathlib import Path
import argparse
import hashlib
import json
import math
import statistics

ROOT=Path(__file__).resolve().parents[2]


def stats(values):
    values=sorted(float(v) for v in values)
    if not values:return None
    return {'count':len(values),'mean_ms':statistics.mean(values),'median_ms':statistics.median(values),
            'p95_ms':values[math.ceil((len(values)-1)*.95)],'p99_ms':values[math.ceil((len(values)-1)*.99)],
            'maximum_ms':values[-1],'frames_over_16_67_ms':sum(v>1000/60 for v in values),
            'frames_over_33_33_ms':sum(v>1000/30 for v in values),'frames_over_100_ms':sum(v>100 for v in values)}


def analyze(tag):
    meta_path=ROOT/f'docs/{tag}_observation.json';samples_path=ROOT/f'docs/{tag}_samples.json'
    meta=json.loads(meta_path.read_text());rows=json.loads(samples_path.read_text());columns=meta['columns']
    assert len(rows)==meta['frame_rows'] and all(len(r)==len(columns) for r in rows)
    index={k:i for i,k in enumerate(columns)}
    def value(row,column):return row[index[column]]
    def collect(group,column):return [value(r,column) for r in group]
    # The startup interval is still retained below, but not a steady-state frame.
    steady=rows[1:]
    summary=stats(collect(steady,'frame_gap_ms'))
    summary['elapsed_sample_seconds']=sum(collect(steady,'frame_gap_ms'))/1000
    summary['fps_from_mean']=1000/summary['mean_ms']
    phases=[]
    for phase in meta['phase_ranges']:
        group=rows[max(1,phase['start_row']):phase['end_row']]
        phases.append({**phase,'frame_times':stats(collect(group,'frame_gap_ms')),
                       'source_bounds':{k:[min(collect(group,k)),max(collect(group,k))] for k in ['source_x','source_y','jump_height_px']},
                       'quality_values':sorted(set(collect(group,'render_scale'))),
                       'active_effect_frames':sum(value(r,'active_fx_tracks')>0 for r in group),
                       'resource_bounds':[min(collect(group,'resource_count')),max(collect(group,'resource_count'))]})
    slow=[]
    for i,row in enumerate(rows):
        if i and value(row,'frame_gap_ms')>1000/60:
            slow.append({'row':i,**dict(zip(columns,row)),
                         'nearby_events':[e for e in meta['events'] if abs(e.get('elapsed_s',-10)-value(row,'elapsed_s'))<.15]})
    pipe=[]
    for event in meta['events']:
        if event['type']=='pipeline_change':
            group=[r for r in steady if abs(value(r,'elapsed_s')-event['elapsed_s'])<.1]
            pipe.append({**event,'nearby_frame_times':stats(collect(group,'frame_gap_ms'))})
    timing={}
    for name in ['scene_cpu_ms','scene_gpu_ms','window_cpu_ms','window_gpu_ms','pre_post_draw_wall_ms','previous_process_ms','previous_physics_ms']:
        values=collect(steady,name)
        timing[name]={'nonzero_samples':sum(v>0 for v in values),'available':any(v>0 for v in values),
                      'observed':stats(values),'note':'All-zero GPU samples mean unavailable in this measurement, not a zero-cost GPU.' if 'gpu' in name and not any(values) else 'Native field; may lag the wall interval.'}
    checks=[{'check':'all_phases_have_rows','pass':all(p['frame_times'] and p['frame_times']['count']>30 for p in phases)},
            {'check':'all_nine_live_actions_observed','pass':set(meta['observed_actions'])==set(['stay','move','dash','attack1','attack2','attack3','jump','jumpattack','hopsmash'])},
            {'check':'door_approach_reaches_source_y216','pass':any(p['name']=='door_approach' and abs(p['source_bounds']['source_y'][0]-216)<.05 for p in phases)},
            {'check':'real_input_produces_more_than_100px_jump','pass':max(collect(rows,'jump_height_px'))>100},
            {'check':'both_effect_tracks_visible','pass':max(collect(rows,'active_fx_tracks'))==2},
            {'check':'both_render_scales_sampled','pass':set(collect(rows,'render_scale'))=={1,2}},
            {'check':'native_motion_interpolation_enabled','pass':meta['native_interpolation']},
            {'check':'each_row_tracks_a_new_drawn_frame','pass':all(value(b,'frames_drawn')>value(a,'frames_drawn') for a,b in zip(rows,rows[1:]))},
            {'check':'music_does_not_restart','pass':meta['music_starts_before']==meta['music_starts_after']==1},
            {'check':'ambience_does_not_restart','pass':meta['ambience_starts_before']==meta['ambience_starts_after']==1}]
    locomotion={}
    if 'walk_active' in columns:
        actions=meta.get('action_names',['stay','move','dash','attack1','attack2','attack3','hopsmash','jump','jumpattack'])
        for action in meta.get('derived_locomotion_actions',['move']):
            active=[r for r in rows if value(r,'walk_active')>0 and int(value(r,'action_id'))==actions.index(action)]
            derived=[r for r in active if value(r,'walk_subframe')>0]
            ids=sorted({int(value(r,'source_frame'))*3+int(value(r,'walk_subframe')) for r in active})
            locomotion[action]={'active_frames':len(active),'derived_frames':len(derived),'phase_ids':ids}
            checks.append({'check':'all24_'+action+'_samples_observed','pass':ids==list(range(24)) and len(derived)>100})
        if meta.get('locomotion_enabled') is False:
            checks.append({'check':'disabled_locomotion_stays_raw_for_all_samples','pass':all(value(r,'walk_active')==0 and value(r,'walk_subframe')==0 for r in rows)})
    result={'study':meta['production_candidate']+' visible native keyboard performance study','tag':tag,'production_candidate':meta['production_candidate'],
            'diagnostics_active':meta.get('diagnostics_active',False),
            'locomotion_enabled':meta.get('locomotion_enabled',bool(locomotion)),
            'walk_samples':locomotion.get('move'),'locomotion_samples':locomotion,
            'summary':summary,'startup_row':dict(zip(columns,rows[0])),'phases':phases,'timing_fields':timing,
            'focused_frame_count':sum(bool(value(r,'focused')) for r in rows),'unfocused_frame_count':sum(not value(r,'focused') for r in rows),
            'pipeline_events':pipe,'slow_frames':slow,'checks':checks,'failed':[c for c in checks if not c['pass']],
            'native_window':meta['native_window'],'source_transition_count':meta['source_transitions'],
            'resource_start':meta['resource_start'],'resource_end':meta['resource_end'],
            'qa_sha256':meta['qa_source_sha256'],'analysis_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'metadata_sha256':hashlib.sha256(meta_path.read_bytes()).hexdigest(),'raw_samples_sha256':hashlib.sha256(samples_path.read_bytes()).hexdigest(),
            'notes':['All slow frames retained, including quality changes and real input actions.',
                     'Main-loop wall intervals are not proof of display presentation or GPU duration.',
                     'These are observations on the current Mac and production sample, not Windows or long-term stability.',
                     'Previous R1/19 1016.389-ms hitch remains unexplained unless independently reproduced and attributed.']}
    (ROOT/f'docs/{tag}_analysis.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'tag':tag,'summary':summary,'checks':len(checks),'failed':result['failed'],'pipeline_events':len(pipe)},ensure_ascii=False))


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('tag');args=parser.parse_args();analyze(args.tag)
