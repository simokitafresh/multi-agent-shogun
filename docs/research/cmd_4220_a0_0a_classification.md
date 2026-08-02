# cmd_4220 A0-0a evidence-backed classification

- Source: `logs/recon_artifacts/kotaro_phase0_threeway_20260802.csv`
- Output: `docs/research/cmd_4220_a0_0a_classification.csv`
- Production readonly as-of: `2026-08-02`
- Data rows: 1885
- DB route: `db_capability_launcher readonly_query`; direct connection and writes: 0.
- Boundary rule: verified ledger date only when equal to expanded switch; otherwise expanded switch; no-switch month uses first SPY trading day after full daily-signature coverage proof.
- Operational start: `portfolio_metrics.data_start_date` (`years=0`).

## Total recount

| Normal | Partial | MTD | 未開始 | Sum | 要調査 | Unclassified | Evidence missing |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1871 | 14 | 0 | 0 | 1885 | 0 | 0 | 0 |

## Boundary evidence

- `expanded_switch_ledger_mismatch`: 8
- `expanded_switch_ledger_verified`: 1682
- `expanded_switch_no_ledger`: 91
- `first_trade_no_switch_full_coverage`: 90
- `operational_start_partial_endpoint`: 14

## Ledger verification

- `not_applicable_no_switch`: 90
- `not_recorded`: 91
- `rejected_mismatch`: 8
- `verified_equal`: 1696

## Decision conditions

| Class | Evidence condition |
|---|---|
| Normal | completed month strictly after operational-start month |
| Partial | year_month equals operational-start month |
| MTD | year_month equals readonly as-of month |
| 未開始 | month precedes operational-start month |

## PF breakdown

| portfolio_id | Normal | Partial | MTD | 未開始 | Total |
|---|---:|---:|---:|---:|---:|
| 015e74dc-26f3-47c5-98ea-414dc4fdf579 | 12 | 0 | 0 | 0 | 12 |
| 0206995c-5aef-4da5-aca7-5bef7a1f4845 | 27 | 0 | 0 | 0 | 27 |
| 10988668-83aa-4f99-a130-48edec4363a6 | 44 | 0 | 0 | 0 | 44 |
| 10bc94d8-bc12-4961-beaf-ca867d75301f | 8 | 0 | 0 | 0 | 8 |
| 13b4b385-3345-4546-8fd4-31d8de485889 | 74 | 0 | 0 | 0 | 74 |
| 21e753ce-72ea-4700-bc65-5b71668d719c | 18 | 0 | 0 | 0 | 18 |
| 2ef6dbc1-2113-4803-a92b-29ae00e60752 | 67 | 1 | 0 | 0 | 68 |
| 323c5dcb-0c4b-44fb-957b-661fef536bef | 23 | 0 | 0 | 0 | 23 |
| 3307d430-a4cd-470a-9750-bea2edc080c4 | 24 | 0 | 0 | 0 | 24 |
| 33b80ea7-e4fe-4553-a477-9f40cf32b6f7 | 49 | 1 | 0 | 0 | 50 |
| 3b8664b4-3c45-427d-8db1-a12bb2ccc113 | 38 | 0 | 0 | 0 | 38 |
| 42f10df9-fae4-4fbb-9761-44841987e615 | 45 | 0 | 0 | 0 | 45 |
| 44fa8aad-9d7d-4424-82f9-665e1028a3b4 | 48 | 0 | 0 | 0 | 48 |
| 4d3cd19b-b441-49a2-b581-038ce058a582 | 37 | 0 | 0 | 0 | 37 |
| 51a06edf-10dc-4b15-ad71-e83d25c53f2a | 50 | 0 | 0 | 0 | 50 |
| 51e95ac2-8142-4ad8-b75d-178b07f03a90 | 30 | 0 | 0 | 0 | 30 |
| 53025dee-0393-4f8b-82c6-4a8c2bbed542 | 26 | 0 | 0 | 0 | 26 |
| 57723979-03ff-4b69-adf6-778b20173528 | 2 | 0 | 0 | 0 | 2 |
| 59e42de5-a7b9-42fe-ac56-bc9b5b42b21c | 36 | 0 | 0 | 0 | 36 |
| 6597f876-bd5a-43f6-ac0d-5f7b9d9be3e0 | 1 | 0 | 0 | 0 | 1 |
| 65db7b53-9e62-4217-b8bb-65cf5445b606 | 63 | 0 | 0 | 0 | 63 |
| 6d9c4b54-8950-40db-b728-d56a65e9ea98 | 5 | 0 | 0 | 0 | 5 |
| 75ae0957-f54e-4462-ad3d-0450630b2184 | 7 | 1 | 0 | 0 | 8 |
| 797623ce-7a15-49f7-b100-c1de6c7b6804 | 8 | 0 | 0 | 0 | 8 |
| 7a21f247-5fd0-4ce1-b9b1-6ca95ebc2d3d | 57 | 1 | 0 | 0 | 58 |
| 81bfb403-bad8-4d7c-9614-566b7c7d30cf | 14 | 0 | 0 | 0 | 14 |
| 856b8336-af00-4401-8ac8-5431c8e20f56 | 65 | 0 | 0 | 0 | 65 |
| 904d3342-8a39-41db-ada7-d6c28fb3e63c | 57 | 1 | 0 | 0 | 58 |
| 9324015c-5f32-4bee-a263-51b4874e86c0 | 109 | 0 | 0 | 0 | 109 |
| 96b3ec70-522c-491d-86bd-6ec7a8459804 | 5 | 0 | 0 | 0 | 5 |
| 99d853fa-3d0e-4b4b-812a-f5b82f8fe2dc | 42 | 1 | 0 | 0 | 43 |
| b1ef6669-0518-4ccd-a1f0-f6a128b21a65 | 17 | 0 | 0 | 0 | 17 |
| b4cb367a-f83d-41b2-889e-25ed0f9aba92 | 42 | 0 | 0 | 0 | 42 |
| bd731ae8-17c5-4605-825e-b2bd42c3efa7 | 33 | 0 | 0 | 0 | 33 |
| bea707ff-f745-4b7d-b43d-8292b98ee4a2 | 5 | 0 | 0 | 0 | 5 |
| bf40cc1d-1f95-4a24-b3fa-ad3dd9016151 | 30 | 0 | 0 | 0 | 30 |
| c144d73a-b407-4135-ab60-bef702f5cf39 | 6 | 0 | 0 | 0 | 6 |
| c2772986-b586-4cd8-904f-3537be68e813 | 35 | 0 | 0 | 0 | 35 |
| c4633d7f-447b-4ec2-a11c-fd849a465ccf | 23 | 1 | 0 | 0 | 24 |
| c52659c4-f63f-4b3b-a154-0c7147963477 | 11 | 0 | 0 | 0 | 11 |
| c6bf9984-3ebf-4638-a674-5b8fa4fbdbaf | 27 | 0 | 0 | 0 | 27 |
| c9cda763-862c-4189-8029-5782d35b7235 | 68 | 0 | 0 | 0 | 68 |
| ca22177c-d34e-412b-829b-8bb9362e934c | 37 | 1 | 0 | 0 | 38 |
| cb4230ba-0e9e-4799-92f0-432007b88484 | 68 | 1 | 0 | 0 | 69 |
| cc60f363-5c6c-46d7-93be-2239ac10dbcb | 21 | 1 | 0 | 0 | 22 |
| d2ca7e6b-9a51-4499-b519-7ca16b3dd135 | 3 | 0 | 0 | 0 | 3 |
| e65db8e2-8e4e-4fe2-9527-7e0b2ddbfe6c | 17 | 1 | 0 | 0 | 18 |
| e805e082-8f46-4af9-8120-b1397535f8d1 | 1 | 0 | 0 | 0 | 1 |
| e89b8a16-4380-43a2-bcbf-3b7ea3a44e85 | 26 | 0 | 0 | 0 | 26 |
| ed2079af-6ea0-4ae4-a7e6-e9bb4935f5a7 | 56 | 0 | 0 | 0 | 56 |
| ed611aa1-e6d6-4dfd-a2ce-da5899235dee | 67 | 1 | 0 | 0 | 68 |
| f16fcd15-e703-4fc5-bc12-2575ca3a612c | 22 | 0 | 0 | 0 | 22 |
| f2d9631d-0e68-4644-b347-f106e43f4ae5 | 16 | 1 | 0 | 0 | 17 |
| f37a9954-9fd3-43c8-ac04-7f69737d96e5 | 44 | 1 | 0 | 0 | 45 |
| f53a8a72-386e-4a43-9e8d-205bbf46462b | 43 | 0 | 0 | 0 | 43 |
| f6a321dd-4c72-4d08-91ce-3d20c676b5d3 | 7 | 0 | 0 | 0 | 7 |
| fc82e757-4ade-4b2b-9af4-49895d96c29f | 55 | 0 | 0 | 0 | 55 |

## Year breakdown

| year | Normal | Partial | MTD | 未開始 | Total |
|---|---:|---:|---:|---:|---:|
| 2012 | 4 | 0 | 0 | 0 | 4 |
| 2013 | 10 | 2 | 0 | 0 | 12 |
| 2014 | 106 | 4 | 0 | 0 | 110 |
| 2015 | 134 | 2 | 0 | 0 | 136 |
| 2016 | 199 | 6 | 0 | 0 | 205 |
| 2017 | 70 | 0 | 0 | 0 | 70 |
| 2018 | 185 | 0 | 0 | 0 | 185 |
| 2019 | 109 | 0 | 0 | 0 | 109 |
| 2020 | 109 | 0 | 0 | 0 | 109 |
| 2021 | 140 | 0 | 0 | 0 | 140 |
| 2022 | 200 | 0 | 0 | 0 | 200 |
| 2023 | 264 | 0 | 0 | 0 | 264 |
| 2024 | 182 | 0 | 0 | 0 | 182 |
| 2025 | 63 | 0 | 0 | 0 | 63 |
| 2026 | 96 | 0 | 0 | 0 | 96 |

## §1d return proposal

> A0-0a本番readonly証拠付き分類(全1,885行、Normal 1,871 / Partial 14 / MTD 0 / 未開始 0、要調査0・未分類0・証拠欠損0): `docs/research/cmd_4220_a0_0a_classification.csv` (判定条件・PF/年代内訳: `docs/research/cmd_4220_a0_0a_classification.md`)
