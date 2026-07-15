# 借贷账户--最近一月表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform)
page_id: 39c617cf-3593-80a2-ad66-fc32d5d4ba67


| 数值类型 | 字段解释 | 字段名称 | 备注 | 字段编码 |
| long | 自增主键ID | 主键ID |  | id |
| varchar(32) | 报告ID | 报告ID |  | id_unqf |
| varchar(32) | 客户ID | 客户ID |  | id_unqp |
| varchar(60) | 账户标识 | 账户标识 |  | account_no |
| varchar(12) | 月份 | 月份 |  | month |
| varchar(12) | 账户状态 | 账户状态 | 对应字典：D1账户：ploan_d1_account_state_codeR1账户：ploan_r1_account_state_codeR2R3账户：ploan_r2r3_account_state_codeR4账户：ploan_r4_account_state_codeC1账户：ploan_c1_account_state_code | account_state |
| int | 余额 | 余额 |  | balance |
| int | 已用额度 | 已用额度 |  | used_amount |
| int | 未出单的大额专项分期余额 | 未出单的大额专项分期余额 |  | lsiw_balance |
| varchar(16) | 贷款五级分类 | 五级分类 | 对应字典：risk_account_level | level5_type |
| int | 剩余还款期数 | 剩余还款期数 |  | remain_repayment_period |
| date | 结算/应还款日 | 结算/应还款日 |  | settle_date |
| int | 本月应还款 | 本月应还款 |  | repayment_amount |
| int | 本月实还款 | 本月实还款 |  | actual_repayment_amount |
| date | 最近一次还款日期 | 最近一次还款日期 |  | latest_repayment_date |
| int | 当前逾期期数 | 当前逾期期数 |  | overdue_period |
| int | 当前逾期总额 | 当前逾期总额 |  | overdue_amount_total |
| int | 逾期31—60天未还本金 | 逾期31—60天未还本金 |  | overdue_pd2_amount |
| int | 逾期61－90天未还本金 | 逾期61－90天未还本金 |  | overdue_pd3_amount |
| int | 逾期91－180天未还本金 | 逾期91－180天未还本金 |  | overdue_pd456_amount |
| int | 逾期180天以上未还本金 | 逾期180天以上未还本金 |  | overdue_pd7_amount |
| int | 透支180天以上未付余额 | 透支180天以上未付余额 |  | overdraw_pd7_amount |
| int | 最近6个月平均使用额度 | 最近6个月平均使用额度 |  | ave6m_use_amount |
| int | 最近6个月平均透支余额 | 最近6个月平均透支余额 |  | ave6m_overdraft_amount |
| int | 最大使用额度 | 最大使用额度 |  | max_use_amount |
| int | 最大透支余额 | 最大透支余额 |  | max_overdraft_amount |
| date | 信息报告日期 | 信息报告日期 |  | info_dt |
| datetime | 插入时间 | 插入时间 |  | time_inst |
可直接用于模型训练的特征共5项：
当前逾期期数（overdue_period）→ 核心风险触发器；
严重逾期本金占比（滚动逾期质量）→ 区分恶意违约的关键指标；
本月还款缺口（repayment_amount - actual_repayment_amount）→ 早期风险预警信号；
近6个月平均使用率（动态负债率）→ 需求紧迫性量化指标；
五级分类标识（二值化高风险类别）→ 监管合规强约束条件。