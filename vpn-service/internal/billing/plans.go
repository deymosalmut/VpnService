package service

import (
	"time"
)

// StaticPlanRegistry holds a fixed set of subscription plans.
type StaticPlanRegistry struct {
	plans map[string]*Plan
}

func NewStaticPlanRegistry() *StaticPlanRegistry {
	r := &StaticPlanRegistry{
		plans: make(map[string]*Plan),
	}

	r.plans["30d"] = &Plan{
		ID:       "30d",
		Name:     "1 месяц",
		Duration: 30 * 24 * time.Hour,
		Price:    29900, // 299.00 RUB in kopecks
		Currency: "RUB",
	}

	r.plans["90d"] = &Plan{
		ID:       "90d",
		Name:     "3 месяца",
		Duration: 90 * 24 * time.Hour,
		Price:    74900, // 749.00 RUB
		Currency: "RUB",
	}

	r.plans["365d"] = &Plan{
		ID:       "365d",
		Name:     "1 год",
		Duration: 365 * 24 * time.Hour,
		Price:    249900, // 2499.00 RUB
		Currency: "RUB",
	}

	return r
}

func (r *StaticPlanRegistry) Get(planID string) (*Plan, error) {
	plan, ok := r.plans[planID]
	if !ok {
		return nil, ErrInvalidPlan
	}
	return plan, nil
}

func (r *StaticPlanRegistry) List() []Plan {
	result := make([]Plan, 0, len(r.plans))
	for _, p := range r.plans {
		result = append(result, *p)
	}
	return result
}
