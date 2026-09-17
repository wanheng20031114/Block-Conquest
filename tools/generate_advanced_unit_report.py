"""Update numerical tables from Godot's live damage resolver export.

Usage: python tools/generate_advanced_unit_report.py .local/advanced-units/integer-balance.json
Authored prose outside the markers is preserved. Raw cases remain ignored.
"""
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
BEGIN = '<!-- BEGIN ADVANCED BALANCE -->'
END = '<!-- END ADVANCED BALANCE -->'


def generate(source: Path) -> str:
    data = json.loads(source.read_text(encoding='utf-8'))
    design = ROOT / 'docs/balance/advanced-units-design.json'
    if hashlib.sha256(design.read_bytes()).hexdigest() != data['design_sha256']:
        raise ValueError('Design changed: rerun the Godot exporter before generating the report')
    ids = data['families']
    units = data['units']
    buildings = data['buildings']
    rows = {tuple(row[:4]): row[4:] for row in data['matchups'] + data['building_matchups']}
    out = []

    def say(text=''):
        out.append(text)

    def table(headers, body):
        say('| ' + ' | '.join(headers) + ' |')
        say('| ' + ' | '.join(['---'] * len(headers)) + ' |')
        for row in body:
            say('| ' + ' | '.join(map(str, row)) + ' |')
        say()

    def n(value):
        return f'{value:g}'

    def adv(key):
        return key + '_advanced'

    def name(key):
        return (units | buildings)[key]['name']

    def hit(a, d, al=0, dl=0):
        return int(rows[a, d, al, dl][1])

    def damage(a, d, al=0, dl=0):
        return rows[a, d, al, dl][0]

    def change(before, after):
        return n(before) if before == after else f'{n(before)} → {n(after)}'

    def percentage(before, after):
        return f'+{(after / before - 1) * 100:.1f}%'

    groups = {'cavalry': '骑兵', 'ranged_infantry': '远程步兵', 'siege': '攻城器'}
    say('## 三、完整数值表')
    say()
    say('以下均为未研究科技的基础值。箭头为“普通 → 高级”，没有箭头表示保持不变。生命、攻击、两类护甲、穿甲和类别附伤全部为整数。')
    say()
    table(['兵种', '生命', '攻击', '近甲', '远甲', '穿甲', '类别附伤', '生命增幅', '攻击增幅'], [
        [name(k), *[change(units[k][p], units[adv(k)][p]) for p in ['hp', 'damage', 'melee_armor', 'ranged_armor', 'armor_penetration']],
         '；'.join(f'对{groups[g]} +{change(units[k]["bonuses"][g], v)}' for g, v in units[adv(k)]['bonuses'].items()) or '无',
         percentage(units[k]['hp'], units[adv(k)]['hp']), percentage(units[k]['damage'], units[adv(k)]['damage'])] for k in ids])
    say('轻骑兵基础攻击7→8是唯一低于15%的直接攻击增幅（14.3%）；整数9会变成28.6%。对远程步兵的护甲前总伤害9→11（+22.2%），同时获得1点远程护甲，强化仍集中于原有职责。')
    say()
    say('以下定位参数在高级版中全部保留；所有单位仍为单体攻击，最小射程为0，只有一把逻辑武器。')
    say()
    table(['兵种', '攻击方式／分类', '攻击间隔', '前摇', '射程', '移速', '视野', '人口', '碰撞半径'], [
        [name(k), ('远程／远程步兵' if units[k]['damage_channel'] == 1 else '近战／' + ('骑兵' if units[k]['combat_class'] == 'cavalry' else '近战步兵')),
         *[n(units[k][p]) for p in ['cooldown', 'windup', 'range', 'speed', 'sight', 'supply', 'radius']]] for k in ids])
    say('时间单位为秒。高级版正式招募价格、训练时间、升级费用与解锁条件本轮不设定：目前没有高级招募入口。下面只是现有普通兵种的经济参照，不能视为高级版报价。')
    say()
    table(['普通兵种', '普通价格／金币', '普通训练时间／秒', '高级招募'], [[name(k), n(units[k]['cost']), n(units[k]['training_seconds']), '未开放'] for k in ids])
    say('## 四、同级互攻与整数门槛')
    say()
    say('行是攻击者，列是受击者；单元格为“普通打普通所需次数 → 高级打高级所需次数”。单个数字表示两者相同。全部是从满血到阵亡的有效命中次数，不含走近、弹道飞行、治疗、集火与先手优势。')
    say()
    table(['攻击者 ↓／目标 →'] + [name(k) for k in ids], [[name(a)] + [change(hit(a, d), hit(adv(a), adv(d))) for d in ids] for a in ids])
    changes = [(a, d, hit(a, d), hit(adv(a), adv(d))) for a in ids for d in ids if hit(a, d) != hit(adv(a), adv(d))]
    exact = 81 - len(changes)
    one = 81 - sum(abs(old - new) > 1 for _, _, old, new in changes)
    worst = max(abs(new / old - 1) for _, _, old, new in changes)
    say(f'**81组中，{exact}组完全相同（{exact/81:.1%}），{one}组相差不超过1次（{one/81:.1%}）；最大相对偏差{worst:.1%}。** 所有高级火枪手同级目标的击杀次数，以及长矛兵打三类骑兵、两类骑兵打三类远程步兵的击杀次数，都与普通级一致。')
    say()
    say('差异超过1次的全部对局如下，不能把它们隐去并声称81组完全不变。')
    say()
    table(['攻击者 → 目标', '次数', '相对变化', '每击实际伤害'], [[f'{name(a)} → {name(d)}', f'{old} → {new}', f'{(new/old-1)*100:+.1f}%', change(damage(a, d), damage(adv(a), adv(d)))] for a, d, old, new in changes if abs(old-new)>1])
    say('盾卫互砍的净伤害为3→4，生命为145→180，因此49→45次，约少8.2%。若把高级盾卫近甲也加到4，净伤害又降回3，反而需要60次（比普通多22.4%）。因此保留3近甲、提升到8远甲，更符合抗远程重装步兵的职责。')
    say()
    say('### 关键克制的双向核查')
    say()
    key_pairs = [('spearman', k) for k in ['knight', 'light_cavalry', 'war_elephant']]
    key_pairs += [(c, r) for c in ['knight', 'light_cavalry'] for r in ['archer', 'crossbowman', 'musketeer']]
    key_pairs += [('musketeer', 'shield_guard'), ('crossbowman', 'shield_guard'), ('archer', 'shield_guard')]
    table(['A／B', 'A击杀B：普通→高级', 'B击杀A：普通→高级'], [[f'{name(a)}／{name(d)}', change(hit(a,d),hit(adv(a),adv(d))),change(hit(d,a),hit(adv(d),adv(a)))] for a,d in key_pairs])
    say('骑士和轻骑兵的反远程步兵加成仍覆盖弓箭手、弩手、火枪手；战象仍完整承受反骑兵附伤。上述表衡量伤害关系，不能仅凭次数断言谁赢：例如骑士1.1秒攻击一次，火枪手2.2秒一次；远程先手与接近时间依旧重要。')
    say()
    say('## 五、跨级对抗')
    say()
    table(['同一兵种', '普通互攻', '高级互攻', '高级击杀普通', '普通击杀高级'], [[name(k),hit(k,k),hit(adv(k),adv(k)),hit(adv(k),k),hit(k,adv(k))] for k in ids])
    say('等级优势是明确的。例如火枪手从普通互攻4发，变成高级打普通3发、普通打高级5发。生命和输出同时提升，会叠加成高于20%的对抗优势，不能把“两个主要属性约20%”等同于“胜率或综合战力仅提升20%”。')
    say()
    say('### 高级攻击普通：完整81组')
    say()
    table(['高级攻击者 ↓／普通目标 →'] + [name(k) for k in ids], [[name(a)] + [hit(adv(a),d) for d in ids] for a in ids])
    say('### 普通攻击高级：完整81组')
    say()
    table(['普通攻击者 ↓／高级目标 →'] + [name(k) for k in ids], [[name(a)] + [hit(a,adv(d)) for d in ids] for a in ids])
    say('## 六、没有高级版的单位和建筑')
    say()
    excluded = ['farmer','engineer','priest','catapult','cannon','heavy_cannon','triple_cannon']
    say('这些目标的数值保持当前版本。表内“普通→高级”只改变行中的攻击者等级，因此击杀它们通常更快。')
    say()
    table(['攻击者 ↓／普通目标 →'] + [name(k) for k in excluded], [[name(a)] + [change(hit(a,d), hit(adv(a),d)) for d in excluded] for a in ids])
    say('反过来，下表只改变受击部队等级：高级单位能承受多少次原版攻城器或支援／建设单位的攻击。')
    say()
    table(['普通攻击者 ↓／目标普通→高级 →'] + [name(k) for k in ids], [[name(a)] + [change(hit(a,d),hit(a,adv(d))) for d in ids] for a in excluded])
    say('三管短炮按一根炮管的一发计算，三根炮管仍独立冷却并可集火；表中不是“轮数”。投石车按每次命中该目标计算，不乘旁边受波及的人数。高级步兵仍承受三管短炮的步兵附伤，不能因为等级而免除克制。')
    say()
    towers = [k for k, v in buildings.items() if v['damage'] > 0]
    say('### 原版防御建筑攻击部队')
    say()
    table(['建筑 ↓／目标普通→高级 →'] + [name(k) for k in ids], [[name(a)] + [change(hit(a,d),hit(a,adv(d))) for d in ids] for a in towers])
    say('多炮口建筑也按一门炮的一次命中计算；范围炮不会把范围内多个目标的伤害相加给单体。建筑自身不接受军队攻防科技。')
    say()
    say('### 部队攻击建筑')
    say()
    targets = ['headquarters','defense_tower','cannon_tower','castle','heavy_fortress']
    table(['部队普通→高级 ↓／建筑 →']+[name(k) for k in targets],[[name(a)]+[change(hit(a,d),hit(adv(a),d)) for d in targets] for a in ids])
    say('高护甲建筑会触发最低1点伤害。例如升级后的低攻击兵种可能越过该门槛，对建筑的相对提升远大于20%；这不是本轮增加的攻城附伤。正式加入可招募模式前，应重点复测这些攻城效率门槛。')
    say()
    say('## 七、学院科技敏感性')
    say()
    say(f'攻击0／I／II／III级的固定加成为{data["attack_bonuses"]}，防御对应为{data["defense_bonuses"]}。科技按原固定点数叠加，不再乘等级倍率，也不提高穿甲和类别附伤。下表比较每种相同科技组合下的普通互攻与高级互攻。')
    say()
    summaries=[]
    for al in range(4):
        for dl in range(4):
            diffs=[(a,d,hit(a,d,al,dl),hit(adv(a),adv(d),al,dl)) for a in ids for d in ids]
            worst_row=max(diffs,key=lambda r:abs(r[3]/r[2]-1))
            a,d,b,e=worst_row
            summaries.append([al,dl,sum(b==e for _,_,b,e in diffs),sum(abs(b-e)<=1 for _,_,b,e in diffs),f'{max(abs(e/b-1) for _,_,b,e in diffs):.1%}',f'{name(a)}→{name(d)}：{b}→{e}'])
    table(['攻击等级','防御等级','完全相同／81','差≤1次／81','最大相对偏差','最大偏差之一'],summaries)
    say('固定点数科技、最低伤害和取整叠加后，部分对局超过基础无科技的10%偏差。此设计保证的是基础等级的近似节奏，不保证每一种科技差都完全一致；为强行对齐而改变科技或给不同等级隐藏倍率，会让规则更难理解。')
    say()
    say('### 双方攻防满级的81组')
    say()
    table(['攻击者 ↓／目标 →']+[name(k) for k in ids],[[name(a)]+[change(hit(a,d,3,3),hit(adv(a),adv(d),3,3)) for d in ids] for a in ids])
    say('牧师的每秒10点治疗和战地休整的恢复量保持不变，高级单位恢复相同比例生命需要更长时间。工程兵仍不能维修这些非攻城器单位。视野、射程、移动、攻击前摇、人口与单位体积未被等级放大。')
    say()
    say(f'本次数值附录由Godot直接计算 **{len(data["matchups"]):,}组单位算例 + {len(data["building_matchups"]):,}组建筑算例**，覆盖25个分析定义（16普通＋9高级设计）和全部16种攻防科技组合。高级设计定义仅在导出器和测试中临时创建；这不代表另外八种已经接入游戏，也不代表完成了11,300场真实战斗。')
    say()
    return '\n'.join(out)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    report = ROOT / 'docs/advanced-units.md'
    text = report.read_text(encoding='utf-8')
    before, rest = text.split(BEGIN, 1)
    _, after = rest.split(END, 1)
    report.write_text(before + BEGIN + '\n\n' + generate(Path(sys.argv[1])) + END + after, encoding='utf-8', newline='\n')
    print(f'Updated {report}')
