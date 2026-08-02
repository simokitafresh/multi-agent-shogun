# cmd_4220 A0-0a classification

- Source: `logs/recon_artifacts/kotaro_phase0_threeway_20260802.csv`
- Output: `docs/research/cmd_4220_a0_0a_classification.csv`
- As-of: `2026-08-02` (source artifact date)
- Data rows: 1885
- Classification order: §0.6 verifier questions Q1→Q4; unresolved required evidence is `要調査`.
- Boundary safeguard: `position_start_date` is not reused as SSOT because §1d invalidates the source oracle's month-start boundary.
- D7: docs/data-only. No runtime behavior changed; executable test scope is exempt. The classifier's own exact recount is the binary contract.

## Decision conditions

| Class | Mechanical condition |
|---|---|
| Normal | Q1 operational start known and reached; historical completed month; Q3 boundary evidence resolved; Q4 separated |
| Partial | Q1 identifies the first incomplete operational interval; completed at next monthly boundary |
| MTD | Q1 operational start known and reached; `year_month == as_of YYYY-MM`; dynamic end is as_of |
| 未開始 | Q1 proves month precedes PF operational start |
| 要調査 | Any required Q1-Q4 evidence is absent or contradictory |

The supplied CSV has neither PF operational-start dates (Q1) nor ledger/expanded-weight monthly-boundary evidence (Q3). Therefore all rows fail visible as `要調査`; guessing from each PF's earliest changed row would confuse a changed-row subset with operational history.

## Total recount

| Normal | Partial | MTD | 未開始 | 要調査 | Sum | Source data rows | Unclassified |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 | 0 | 0 | 0 | 1885 | 1885 | 1885 | 0 |

## PF breakdown

| portfolio_id | Normal | Partial | MTD | 未開始 | 要調査 | Total |
|---|---:|---:|---:|---:|---:|---:|
| 015e74dc-26f3-47c5-98ea-414dc4fdf579 | 0 | 0 | 0 | 0 | 12 | 12 |
| 0206995c-5aef-4da5-aca7-5bef7a1f4845 | 0 | 0 | 0 | 0 | 27 | 27 |
| 10988668-83aa-4f99-a130-48edec4363a6 | 0 | 0 | 0 | 0 | 44 | 44 |
| 10bc94d8-bc12-4961-beaf-ca867d75301f | 0 | 0 | 0 | 0 | 8 | 8 |
| 13b4b385-3345-4546-8fd4-31d8de485889 | 0 | 0 | 0 | 0 | 74 | 74 |
| 21e753ce-72ea-4700-bc65-5b71668d719c | 0 | 0 | 0 | 0 | 18 | 18 |
| 2ef6dbc1-2113-4803-a92b-29ae00e60752 | 0 | 0 | 0 | 0 | 68 | 68 |
| 323c5dcb-0c4b-44fb-957b-661fef536bef | 0 | 0 | 0 | 0 | 23 | 23 |
| 3307d430-a4cd-470a-9750-bea2edc080c4 | 0 | 0 | 0 | 0 | 24 | 24 |
| 33b80ea7-e4fe-4553-a477-9f40cf32b6f7 | 0 | 0 | 0 | 0 | 50 | 50 |
| 3b8664b4-3c45-427d-8db1-a12bb2ccc113 | 0 | 0 | 0 | 0 | 38 | 38 |
| 42f10df9-fae4-4fbb-9761-44841987e615 | 0 | 0 | 0 | 0 | 45 | 45 |
| 44fa8aad-9d7d-4424-82f9-665e1028a3b4 | 0 | 0 | 0 | 0 | 48 | 48 |
| 4d3cd19b-b441-49a2-b581-038ce058a582 | 0 | 0 | 0 | 0 | 37 | 37 |
| 51a06edf-10dc-4b15-ad71-e83d25c53f2a | 0 | 0 | 0 | 0 | 50 | 50 |
| 51e95ac2-8142-4ad8-b75d-178b07f03a90 | 0 | 0 | 0 | 0 | 30 | 30 |
| 53025dee-0393-4f8b-82c6-4a8c2bbed542 | 0 | 0 | 0 | 0 | 26 | 26 |
| 57723979-03ff-4b69-adf6-778b20173528 | 0 | 0 | 0 | 0 | 2 | 2 |
| 59e42de5-a7b9-42fe-ac56-bc9b5b42b21c | 0 | 0 | 0 | 0 | 36 | 36 |
| 6597f876-bd5a-43f6-ac0d-5f7b9d9be3e0 | 0 | 0 | 0 | 0 | 1 | 1 |
| 65db7b53-9e62-4217-b8bb-65cf5445b606 | 0 | 0 | 0 | 0 | 63 | 63 |
| 6d9c4b54-8950-40db-b728-d56a65e9ea98 | 0 | 0 | 0 | 0 | 5 | 5 |
| 75ae0957-f54e-4462-ad3d-0450630b2184 | 0 | 0 | 0 | 0 | 8 | 8 |
| 797623ce-7a15-49f7-b100-c1de6c7b6804 | 0 | 0 | 0 | 0 | 8 | 8 |
| 7a21f247-5fd0-4ce1-b9b1-6ca95ebc2d3d | 0 | 0 | 0 | 0 | 58 | 58 |
| 81bfb403-bad8-4d7c-9614-566b7c7d30cf | 0 | 0 | 0 | 0 | 14 | 14 |
| 856b8336-af00-4401-8ac8-5431c8e20f56 | 0 | 0 | 0 | 0 | 65 | 65 |
| 904d3342-8a39-41db-ada7-d6c28fb3e63c | 0 | 0 | 0 | 0 | 58 | 58 |
| 9324015c-5f32-4bee-a263-51b4874e86c0 | 0 | 0 | 0 | 0 | 109 | 109 |
| 96b3ec70-522c-491d-86bd-6ec7a8459804 | 0 | 0 | 0 | 0 | 5 | 5 |
| 99d853fa-3d0e-4b4b-812a-f5b82f8fe2dc | 0 | 0 | 0 | 0 | 43 | 43 |
| b1ef6669-0518-4ccd-a1f0-f6a128b21a65 | 0 | 0 | 0 | 0 | 17 | 17 |
| b4cb367a-f83d-41b2-889e-25ed0f9aba92 | 0 | 0 | 0 | 0 | 42 | 42 |
| bd731ae8-17c5-4605-825e-b2bd42c3efa7 | 0 | 0 | 0 | 0 | 33 | 33 |
| bea707ff-f745-4b7d-b43d-8292b98ee4a2 | 0 | 0 | 0 | 0 | 5 | 5 |
| bf40cc1d-1f95-4a24-b3fa-ad3dd9016151 | 0 | 0 | 0 | 0 | 30 | 30 |
| c144d73a-b407-4135-ab60-bef702f5cf39 | 0 | 0 | 0 | 0 | 6 | 6 |
| c2772986-b586-4cd8-904f-3537be68e813 | 0 | 0 | 0 | 0 | 35 | 35 |
| c4633d7f-447b-4ec2-a11c-fd849a465ccf | 0 | 0 | 0 | 0 | 24 | 24 |
| c52659c4-f63f-4b3b-a154-0c7147963477 | 0 | 0 | 0 | 0 | 11 | 11 |
| c6bf9984-3ebf-4638-a674-5b8fa4fbdbaf | 0 | 0 | 0 | 0 | 27 | 27 |
| c9cda763-862c-4189-8029-5782d35b7235 | 0 | 0 | 0 | 0 | 68 | 68 |
| ca22177c-d34e-412b-829b-8bb9362e934c | 0 | 0 | 0 | 0 | 38 | 38 |
| cb4230ba-0e9e-4799-92f0-432007b88484 | 0 | 0 | 0 | 0 | 69 | 69 |
| cc60f363-5c6c-46d7-93be-2239ac10dbcb | 0 | 0 | 0 | 0 | 22 | 22 |
| d2ca7e6b-9a51-4499-b519-7ca16b3dd135 | 0 | 0 | 0 | 0 | 3 | 3 |
| e65db8e2-8e4e-4fe2-9527-7e0b2ddbfe6c | 0 | 0 | 0 | 0 | 18 | 18 |
| e805e082-8f46-4af9-8120-b1397535f8d1 | 0 | 0 | 0 | 0 | 1 | 1 |
| e89b8a16-4380-43a2-bcbf-3b7ea3a44e85 | 0 | 0 | 0 | 0 | 26 | 26 |
| ed2079af-6ea0-4ae4-a7e6-e9bb4935f5a7 | 0 | 0 | 0 | 0 | 56 | 56 |
| ed611aa1-e6d6-4dfd-a2ce-da5899235dee | 0 | 0 | 0 | 0 | 68 | 68 |
| f16fcd15-e703-4fc5-bc12-2575ca3a612c | 0 | 0 | 0 | 0 | 22 | 22 |
| f2d9631d-0e68-4644-b347-f106e43f4ae5 | 0 | 0 | 0 | 0 | 17 | 17 |
| f37a9954-9fd3-43c8-ac04-7f69737d96e5 | 0 | 0 | 0 | 0 | 45 | 45 |
| f53a8a72-386e-4a43-9e8d-205bbf46462b | 0 | 0 | 0 | 0 | 43 | 43 |
| f6a321dd-4c72-4d08-91ce-3d20c676b5d3 | 0 | 0 | 0 | 0 | 7 | 7 |
| fc82e757-4ade-4b2b-9af4-49895d96c29f | 0 | 0 | 0 | 0 | 55 | 55 |

## Year breakdown

| year | Normal | Partial | MTD | 未開始 | 要調査 | Total |
|---|---:|---:|---:|---:|---:|---:|
| 2012 | 0 | 0 | 0 | 0 | 4 | 4 |
| 2013 | 0 | 0 | 0 | 0 | 12 | 12 |
| 2014 | 0 | 0 | 0 | 0 | 110 | 110 |
| 2015 | 0 | 0 | 0 | 0 | 136 | 136 |
| 2016 | 0 | 0 | 0 | 0 | 205 | 205 |
| 2017 | 0 | 0 | 0 | 0 | 70 | 70 |
| 2018 | 0 | 0 | 0 | 0 | 185 | 185 |
| 2019 | 0 | 0 | 0 | 0 | 109 | 109 |
| 2020 | 0 | 0 | 0 | 0 | 109 | 109 |
| 2021 | 0 | 0 | 0 | 0 | 140 | 140 |
| 2022 | 0 | 0 | 0 | 0 | 200 | 200 |
| 2023 | 0 | 0 | 0 | 0 | 264 | 264 |
| 2024 | 0 | 0 | 0 | 0 | 182 | 182 |
| 2025 | 0 | 0 | 0 | 0 | 63 | 63 |
| 2026 | 0 | 0 | 0 | 0 | 96 | 96 |
