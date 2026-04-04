import httpx
import json

try:
    with httpx.Client(base_url='http://127.0.0.1:8000', timeout=10.0) as client:
        r = client.post('/auth/google', json={
            'email': 'buyer@example.com',
            'name': 'Test Buyer',
            'google_id': 'buy123',
            'photo_url': ''
        })
        print("Login status:", r.status_code)
        if r.status_code != 200:
            print(r.text)
            exit(1)
        token = r.json()['access_token']
        buyer_id = r.json()['user']['id']
        
        # update profile to be buyer and completed
        client.post('/auth/complete-profile', headers={'Authorization': f'Bearer {token}'}, json={
            'role': 'buyer', 'mobile_number': '9999999999', 'district': 'Chennai'
        })
        
        # also create a farmer
        rf = client.post('/auth/google', json={
            'email': 'farmer@example.com',
            'name': 'Test Farmer',
            'google_id': 'farm123',
            'photo_url': ''
        })
        ftoken = rf.json()['access_token']
        client.post('/auth/complete-profile', headers={'Authorization': f'Bearer {ftoken}'}, json={
            'role': 'farmer', 'mobile_number': '8888888888', 'district': 'Erode'
        })
        
        # create crop
        rc = client.post('/crops', headers={'Authorization': f'Bearer {ftoken}'}, json={
            'name': 'Test Wheat', 'category': 'Wheat', 'price_per_kg': 50.0, 'stock_kg': 1000
        })
        print("Crop status:", rc.status_code)
        if rc.status_code != 201:
            print(rc.text)
            exit(1)
            
        crop_id = rc.json()['id']
        
        # array of order tests
        print("Creating order...")
        ro = client.post('/orders', headers={'Authorization': f'Bearer {token}'}, json={
            'crop_id': crop_id, 'quantity_kg': 10.0, 'delivery_address': 'Some Address'
        })
        print("Order status:", ro.status_code)
        print("Order response:", ro.text)
        
except Exception as e:
    print('Failed:', e)
