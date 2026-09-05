#!/usr/bin/env python3
"""Normalize the official USDA SR Legacy JSON zip. No network/API key at runtime.

python3 Scripts/import_food_catalog.py /tmp/usda.zip Dayvera/Resources/FoodCatalog.json
Source: https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2018-04.zip
"""
import hashlib
import json
import math
import sys
import zipfile
from pathlib import Path


def convert(source, destination):
    with zipfile.ZipFile(source) as archive:
        raw = archive.read(next(n for n in archive.namelist() if n.endswith('.json')))
    foods = []
    for item in json.loads(raw)['SRLegacyFoods']:
        values = {n['nutrient']['id']: n.get('amount') for n in item['foodNutrients']}
        nutrients = {k: values.get(n) for k, n in [('calories', 1008), ('protein', 1003), ('carbs', 1005), ('fat', 1004)]}
        if any(v is None or not math.isfinite(v) or v < 0 for v in nutrients.values()):
            continue  # Unknown is never silently converted to zero.
        portions = []
        for p in item.get('foodPortions', []):
            grams = p.get('gramWeight', 0)
            if grams <= 0 or not math.isfinite(grams):
                continue
            label = f"{p.get('amount', 1):g} {p.get('modifier', 'portion')}"
            portions.append({'label': label.strip(), 'grams': grams})
        foods.append({'id': str(item['fdcId']), 'name': item['description'], 'nutrients': nutrients, 'portions': portions})
    foods.sort(key=lambda f: int(f['id']))
    result = {'version': 'USDA-SR-Legacy-2018-04', 'source': 'https://fdc.nal.usda.gov/download-datasets/',
              'sourceSHA256': hashlib.sha256(raw).hexdigest(), 'foods': foods}
    Path(destination).write_text(json.dumps(result, separators=(',', ':'), ensure_ascii=False) + '\n')
    print(f'Wrote {len(foods)} foods with complete macro data')


if __name__ == '__main__':
    convert(sys.argv[1], sys.argv[2])
