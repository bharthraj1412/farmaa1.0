import requests

try:
    print('Testing Production Vercel...')
    url = 'https://farmaa1-0.vercel.app'
    # test crops
    r1 = requests.get(f'{url}/crops', timeout=10.0)
    print('/crops ->', r1.status_code)
    
    # test market
    r2 = requests.get(f'{url}/market', timeout=10.0)
    print('/market ->', r2.status_code)
    
    # test ai error ?
    r3 = requests.post(f'{url}/ai/chat', json={'messages': [{'role':'user','content':'hi'}]}, timeout=10.0)
    print('/ai/chat ->', r3.status_code)
    if r3.status_code == 500:
        print('AI response:', r3.text)
            
except Exception as e:
    print('Failed:', e)
